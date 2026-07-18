import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../face_match_config.dart';
import '../face_match_kit_base.dart';
import '../face_match_models.dart';
import '../liveness.dart';
import 'camera_helpers.dart';
import 'face_camera_frame.dart';
import 'face_match_theme.dart';

class FaceVerificationView extends StatefulWidget {
  final FaceTemplate template;
  final FaceMatchKit? kit;
  final FaceMatchConfig config;
  final ValueChanged<VerificationResult> onCompleted;
  final FaceMatchTheme theme;
  final FaceMatchTexts texts;
  final FaceOverlayBuilder? overlayBuilder;

  const FaceVerificationView({
    super.key,
    required this.template,
    this.kit,
    this.config = const FaceMatchConfig(),
    required this.onCompleted,
    this.theme = const FaceMatchTheme(),
    this.texts = const FaceMatchTexts(),
    this.overlayBuilder,
  });

  @override
  State<FaceVerificationView> createState() => _FaceVerificationViewState();
}

class _FaceVerificationViewState extends State<FaceVerificationView>
    with WidgetsBindingObserver {
  FaceMatchKit? _kit;
  CameraController? _camera;
  CameraDescription? _description;
  LivenessSession? _liveness;
  DetectedFace? _face;
  FaceMatchFailure? _failure;
  VerificationResult? _result;
  var _busy = false;
  var _processingFrame = false;
  var _ownsKit = false;
  var _initializing = false;
  var _appActive = true;
  var _initializationGeneration = 0;
  var _missingFaceFrames = 0;
  var _autoCaptureScheduled = false;

  FaceMatchConfig get _effectiveConfig => widget.kit?.config ?? widget.config;
  bool get _livenessComplete =>
      !_effectiveConfig.livenessEnabled || (_liveness?.isComplete ?? false);
  bool get _captureReady =>
      _livenessComplete &&
      _face != null &&
      (_kit?.evaluateQuality(_face!, verification: true).isAcceptable ??
          false) &&
      !_busy &&
      _result == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant FaceVerificationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.template, widget.template)) {
      unawaited(_retry());
    }
  }

  Future<void> _initialize() async {
    if (_initializing || _camera != null || !_appActive) return;
    _initializing = true;
    final generation = _initializationGeneration;
    CameraController? controller;
    try {
      _effectiveConfig.validate();
      if (_kit == null) {
        final ownsCandidate = widget.kit == null;
        final candidate =
            widget.kit ?? await FaceMatchKit.create(config: _effectiveConfig);
        if (!_isCurrentInitialization(generation)) {
          if (ownsCandidate) await candidate.dispose();
          return;
        }
        _kit = candidate;
        _ownsKit = ownsCandidate;
      }
      _resetLiveness();
      final available = await availableCameras();
      if (!_isCurrentInitialization(generation)) return;
      final description = available.cast<CameraDescription?>().firstWhere(
        (camera) => camera?.lensDirection == CameraLensDirection.front,
        orElse: () => null,
      );
      if (description == null) throw StateError(widget.texts.noCamera);
      controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!_isCurrentInitialization(generation)) return;
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!_isCurrentInitialization(generation)) return;
      _description = description;
      _camera = controller;
      await controller.startImageStream(_processFrame);
      controller = null;
      _setState(() {});
    } catch (error) {
      if (identical(_camera, controller)) _camera = null;
      await controller?.dispose();
      controller = null;
      debugPrint('Face verification initialization failed: $error');
      if (!_isCurrentInitialization(generation)) return;
      _setState(() => _failure = _cameraFailure(error, initialization: true));
    } finally {
      await controller?.dispose();
      _initializing = false;
      if (mounted &&
          _appActive &&
          _camera == null &&
          generation != _initializationGeneration) {
        unawaited(_initialize());
      }
    }
  }

  void _resetLiveness() {
    _missingFaceFrames = 0;
    _autoCaptureScheduled = false;
    _liveness = _effectiveConfig.livenessEnabled
        ? LivenessSession(
            LivenessChallenge.random(
              actionCount: _effectiveConfig.livenessActionCount,
            ),
            actionTimeout: _effectiveConfig.livenessActionTimeout,
          )
        : null;
  }

  Future<void> _processFrame(CameraImage image) async {
    final camera = _camera;
    final description = _description;
    if (_processingFrame ||
        _busy ||
        !mounted ||
        camera == null ||
        description == null ||
        _kit == null) {
      return;
    }
    _processingFrame = true;
    try {
      final detection = await _kit!.detectCameraImage(
        image,
        rotation: rotationForCameraFrame(
          width: image.width,
          height: image.height,
          sensorOrientation: description.sensorOrientation,
          isFrontCamera: description.lensDirection == CameraLensDirection.front,
          deviceOrientation: camera.value.deviceOrientation,
        ),
        isBgra: Platform.isIOS,
      );
      final face = detection.hasExactlyOneFace ? detection.faces.single : null;
      var livenessJustCompleted = false;
      if (face == null) {
        _missingFaceFrames++;
        if (_missingFaceFrames >= _effectiveConfig.livenessFaceLossTolerance) {
          _resetLiveness();
        }
      } else {
        _missingFaceFrames = 0;
        if (!_livenessComplete) {
          final wasComplete = _liveness!.isComplete;
          _liveness!.update(face);
          livenessJustCompleted = !wasComplete && _liveness!.isComplete;
        }
      }
      final quality = face == null
          ? null
          : _kit!.evaluateQuality(face, verification: true);
      _setState(() {
        _face = face;
        if (quality != null && !quality.isAcceptable) {
          _failure = FaceMatchFailure(
            FaceMatchErrorCode.lowQuality,
            quality.issues.first,
          );
        } else if (detection.failure?.code != FaceMatchErrorCode.noFace) {
          _failure = detection.failure;
        } else {
          _failure = null;
        }
      });
      if (livenessJustCompleted && !_autoCaptureScheduled) {
        _autoCaptureScheduled = true;
        unawaited(Future<void>.delayed(Duration.zero, _verify));
      }
    } finally {
      await Future<void>.delayed(_effectiveConfig.liveDetectionInterval);
      _processingFrame = false;
    }
  }

  Future<void> _verify() async {
    if (!_captureReady || _camera == null) {
      _autoCaptureScheduled = false;
      return;
    }
    _setState(() => _busy = true);
    XFile? file;
    try {
      await _camera!.stopImageStream();
      file = await _camera!.takePicture();
      final bytes = await file.readAsBytes();
      final result = await _kit!.verify(
        imageBytes: bytes,
        template: widget.template,
        threshold: _effectiveConfig.verificationThreshold,
      );
      _setState(() {
        _result = result;
        _failure = result.failure;
      });
      _notifyCompleted(result);
    } catch (error) {
      debugPrint('Face verification capture failed: $error');
      _resetLiveness();
      _setState(() => _failure = _cameraFailure(error));
      await _ensureImageStream();
    } finally {
      if (file != null) await _deleteCapture(file.path);
      _setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    _setState(() {
      _failure = null;
      _result = null;
      _face = null;
      _resetLiveness();
    });
    if (!(_camera?.value.isStreamingImages ?? false)) {
      await _camera?.startImageStream(_processFrame);
    }
  }

  String get _instruction {
    if (_result?.isMatch ?? false) return widget.texts.success;
    if (!_livenessComplete) {
      return widget.texts.liveness(_liveness!.currentAction!);
    }
    return widget.texts.lookStraight;
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return ColoredBox(
      color: widget.theme.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: camera == null || !camera.value.isInitialized
            ? Center(
                child: Text(
                  _failure?.message ?? widget.texts.initializing,
                  style: TextStyle(
                    color: _failure == null
                        ? widget.theme.foregroundColor
                        : widget.theme.errorColor,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaceCameraFrame(
                    controller: camera,
                    face: _face,
                    isReady: _captureReady,
                    theme: widget.theme,
                    overlayBuilder: widget.overlayBuilder,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _failure?.message ?? _instruction,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _failure == null
                          ? widget.theme.foregroundColor
                          : widget.theme.errorColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.texts.similarity(_result!.similarity),
                      style: TextStyle(color: widget.theme.foregroundColor),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_result == null)
                    FilledButton.icon(
                      onPressed: _captureReady ? _verify : null,
                      icon: const Icon(Icons.face_outlined),
                      label: Text(
                        _busy ? widget.texts.processing : widget.texts.verify,
                      ),
                    )
                  else if (!_result!.isMatch)
                    OutlinedButton(
                      onPressed: _retry,
                      child: Text(widget.texts.retry),
                    ),
                ],
              ),
      ),
    );
  }

  void _setState(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _camera == null && !_busy) {
      unawaited(_initialize());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
    }
  }

  Future<void> _disposeCamera() async {
    _initializationGeneration++;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  bool _isCurrentInitialization(int generation) =>
      mounted && _appActive && generation == _initializationGeneration;

  Future<void> _ensureImageStream() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isStreamingImages) {
      return;
    }
    await camera.startImageStream(_processFrame);
  }

  FaceMatchFailure _cameraFailure(Object error, {bool initialization = false}) {
    if (error is StateError && error.message == widget.texts.noCamera) {
      return FaceMatchFailure(
        FaceMatchErrorCode.cameraUnavailable,
        widget.texts.noCamera,
      );
    }
    if (error is CameraException) {
      final code = error.code.toLowerCase();
      if (code.contains('accessdenied') || code.contains('restricted')) {
        return FaceMatchFailure(
          FaceMatchErrorCode.permissionDenied,
          widget.texts.permissionDenied,
        );
      }
    }
    return FaceMatchFailure(
      FaceMatchErrorCode.cameraFailure,
      initialization
          ? widget.texts.cameraStartFailed
          : widget.texts.captureFailed,
    );
  }

  void _notifyCompleted(VerificationResult result) {
    try {
      widget.onCompleted(result);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'face_match_kit',
          context: ErrorDescription('while calling onCompleted'),
        ),
      );
    }
  }

  Future<void> _deleteCapture(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Camera plugin temporary files may already have been removed.
    }
  }

  @override
  void dispose() {
    _appActive = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    if (_ownsKit) unawaited(_kit?.dispose());
    super.dispose();
  }
}

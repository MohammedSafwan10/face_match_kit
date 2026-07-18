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

class FaceEnrollmentView extends StatefulWidget {
  final FaceMatchKit? kit;
  final FaceMatchConfig config;
  final ValueChanged<EnrollmentResult> onCompleted;
  final FaceMatchTheme theme;
  final FaceMatchTexts texts;
  final FaceOverlayBuilder? overlayBuilder;

  const FaceEnrollmentView({
    super.key,
    this.kit,
    this.config = const FaceMatchConfig(),
    required this.onCompleted,
    this.theme = const FaceMatchTheme(),
    this.texts = const FaceMatchTexts(),
    this.overlayBuilder,
  });

  @override
  State<FaceEnrollmentView> createState() => _FaceEnrollmentViewState();
}

class _FaceEnrollmentViewState extends State<FaceEnrollmentView>
    with WidgetsBindingObserver {
  FaceMatchKit? _kit;
  CameraController? _camera;
  CameraDescription? _description;
  LivenessSession? _liveness;
  DetectedFace? _face;
  FaceMatchFailure? _failure;
  final List<FaceSample> _samples = [];
  var _busy = false;
  var _processingFrame = false;
  var _ownsKit = false;
  var _initializing = false;
  var _appActive = true;
  var _initializationGeneration = 0;
  var _missingFaceFrames = 0;
  var _autoCaptureScheduled = false;

  FaceMatchConfig get _effectiveConfig => widget.kit?.config ?? widget.config;
  FacePose get _pose => FacePose.values[_samples.length.clamp(0, 2)];
  bool get _livenessComplete =>
      !_effectiveConfig.livenessEnabled || (_liveness?.isComplete ?? false);
  bool get _captureReady =>
      _livenessComplete &&
      _face != null &&
      poseIsReady(_pose, _face) &&
      (_kit?.evaluateQuality(_face!).isAcceptable ?? false) &&
      !_busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializing || _camera != null || !_appActive) return;
    _initializing = true;
    final generation = _initializationGeneration;
    CameraController? controller;
    setStateIfMounted(() => _failure = null);
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
      if (description == null) {
        throw StateError(widget.texts.noCamera);
      }
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
      setStateIfMounted(() {});
    } catch (error) {
      if (identical(_camera, controller)) _camera = null;
      await controller?.dispose();
      controller = null;
      debugPrint('Face enrollment initialization failed: $error');
      if (!_isCurrentInitialization(generation)) return;
      setStateIfMounted(
        () => _failure = _cameraFailure(error, initialization: true),
      );
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
      final result = await _kit!.detectCameraImage(
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
      final face = result.hasExactlyOneFace ? result.faces.single : null;
      var livenessJustCompleted = false;
      if (face == null) {
        _missingFaceFrames++;
        if (_samples.isEmpty &&
            _missingFaceFrames >= _effectiveConfig.livenessFaceLossTolerance) {
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
      final quality = face == null ? null : _kit!.evaluateQuality(face);
      setStateIfMounted(() {
        _face = face;
        _failure = quality != null && !quality.isAcceptable
            ? FaceMatchFailure(
                FaceMatchErrorCode.lowQuality,
                quality.issues.first,
              )
            : result.failure?.code == FaceMatchErrorCode.noFace
            ? null
            : result.failure;
      });
      if (livenessJustCompleted && _samples.isEmpty && !_autoCaptureScheduled) {
        _autoCaptureScheduled = true;
        unawaited(Future<void>.delayed(Duration.zero, _capture));
      }
    } finally {
      await Future<void>.delayed(_effectiveConfig.liveDetectionInterval);
      _processingFrame = false;
    }
  }

  Future<void> _capture() async {
    if (!_captureReady || _camera == null) {
      _autoCaptureScheduled = false;
      return;
    }
    setState(() => _busy = true);
    XFile? file;
    try {
      await _camera!.stopImageStream();
      file = await _camera!.takePicture();
      final bytes = await file.readAsBytes();
      _samples.add(FaceSample(imageBytes: bytes, pose: _pose));
      _face = null;
      if (_samples.length == FacePose.values.length) {
        final result = await _kit!.enroll(samples: List.of(_samples));
        _samples.clear();
        if (result.isSuccess) {
          _notifyCompleted(result);
        } else {
          _failure = result.failure;
          _resetLiveness();
          await _ensureImageStream();
        }
      } else {
        await _ensureImageStream();
      }
    } catch (error) {
      debugPrint('Face enrollment capture failed: $error');
      _failure = _cameraFailure(error);
      if (_samples.isEmpty) _resetLiveness();
      await _ensureImageStream();
    } finally {
      if (file != null) await _deleteCapture(file.path);
      setStateIfMounted(() => _busy = false);
    }
  }

  String get _instruction {
    if (!_livenessComplete) {
      return widget.texts.liveness(_liveness!.currentAction!);
    }
    return widget.texts.pose(_pose);
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return ColoredBox(
      color: widget.theme.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: camera == null || !camera.value.isInitialized
            ? _Status(
                message: _failure?.message ?? widget.texts.initializing,
                color: _failure == null
                    ? widget.theme.foregroundColor
                    : widget.theme.errorColor,
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
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _samples.length / FacePose.values.length,
                    color: widget.theme.accentColor,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _captureReady ? _capture : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _busy ? widget.texts.processing : widget.texts.capture,
                    ),
                  ),
                ],
              ),
      ),
    );
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

  void setStateIfMounted(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> _disposeCamera() async {
    _initializationGeneration++;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  bool _isCurrentInitialization(int generation) =>
      mounted && _appActive && generation == _initializationGeneration;

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

  void _notifyCompleted(EnrollmentResult result) {
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
    _samples.clear();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    if (_ownsKit) unawaited(_kit?.dispose());
    super.dispose();
  }
}

class _Status extends StatelessWidget {
  final String message;
  final Color color;

  const _Status({required this.message, required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color),
      ),
    ),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../face_match_config.dart';
import '../face_match_kit_base.dart';
import '../face_match_models.dart';
import '../liveness.dart';
import 'camera_helpers.dart';
import 'face_capture_chrome.dart';
import 'face_camera_frame.dart';
import 'face_match_theme.dart';
import 'liveness_guidance.dart';

class FaceVerificationView extends StatefulWidget {
  final FaceTemplate template;
  final FaceMatchKit? kit;
  final FaceMatchConfig config;
  final ValueChanged<VerificationResult> onCompleted;
  final ValueChanged<FaceMatchFailure>? onError;
  final FaceMatchTheme theme;
  final FaceMatchTexts texts;
  final FaceOverlayBuilder? overlayBuilder;
  final bool showDebugInfo;

  const FaceVerificationView({
    super.key,
    required this.template,
    this.kit,
    this.config = const FaceMatchConfig(),
    required this.onCompleted,
    this.onError,
    this.theme = const FaceMatchTheme(),
    this.texts = const FaceMatchTexts(),
    this.overlayBuilder,
    this.showDebugInfo = false,
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
  var _reconfiguring = false;
  var _appActive = true;
  var _initializationGeneration = 0;
  var _operationGeneration = 0;
  var _missingFaceFrames = 0;
  var _autoCaptureScheduled = false;
  var _retryAfterOperation = false;
  DateTime? _livenessCompletedAt;

  FaceMatchConfig get _effectiveConfig => widget.kit?.config ?? widget.config;
  bool get _livenessExpired =>
      _livenessCompletedAt != null &&
      DateTime.now().difference(_livenessCompletedAt!) >
          _effectiveConfig.livenessCompletionTimeout;
  bool get _livenessComplete =>
      !_effectiveConfig.livenessEnabled ||
      ((_liveness?.isComplete ?? false) && !_livenessExpired);
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
    final kitChanged = !identical(oldWidget.kit, widget.kit);
    final configChanged =
        widget.kit == null && oldWidget.config != widget.config;
    if (kitChanged || configChanged) {
      unawaited(_reconfigure());
      return;
    }
    if (!identical(oldWidget.template, widget.template)) {
      _operationGeneration++;
      if (_busy) {
        _retryAfterOperation = true;
      } else {
        unawaited(_retry());
      }
    }
  }

  Future<void> _reconfigure() async {
    if (_reconfiguring) return;
    _reconfiguring = true;
    try {
      _operationGeneration++;
      await _disposeCamera();
      final oldKit = _kit;
      final disposeOldKit = _ownsKit;
      _kit = null;
      _ownsKit = false;
      _retryAfterOperation = false;
      _setState(() {
        _face = null;
        _failure = null;
        _result = null;
      });
      if (disposeOldKit) await oldKit?.dispose();
    } finally {
      _reconfiguring = false;
      if (mounted && _appActive) unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    if (_initializing || _reconfiguring || _camera != null || !_appActive) {
      return;
    }
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
        // Keep CameraX output compatible with the detector's multi-plane
        // Android frame converter. Requested NV21 arrives as one undecodable
        // plane and otherwise looks like a permanent "no face" result.
        imageFormatGroup: cameraImageFormatForPlatform(defaultTargetPlatform),
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
      if (widget.showDebugInfo) {
        debugPrint('Face verification initialization failed: $error');
      }
      if (!_isCurrentInitialization(generation)) return;
      final failure = _cameraFailure(error, initialization: true);
      _setState(() => _failure = failure);
      _notifyError(failure);
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
    _livenessCompletedAt = null;
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
    final generation = _initializationGeneration;
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
      if (!mounted ||
          generation != _initializationGeneration ||
          !identical(camera, _camera)) {
        return;
      }
      final face = detection.hasExactlyOneFace ? detection.faces.single : null;
      var livenessJustCompleted = false;
      if (_livenessExpired) _resetLiveness();
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
          if (livenessJustCompleted) _livenessCompletedAt = DateTime.now();
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
    final operation = ++_operationGeneration;
    final camera = _camera!;
    final template = widget.template;
    final threshold = _effectiveConfig.verificationThreshold;
    _setState(() => _busy = true);
    XFile? file;
    try {
      await camera.stopImageStream();
      file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      if (!_isCurrentOperation(operation)) return;
      final result = await _kit!.verify(
        imageBytes: bytes,
        template: template,
        threshold: threshold,
      );
      if (!_isCurrentOperation(operation)) return;
      _setState(() {
        _result = result;
        _failure = result.failure;
      });
      _notifyCompleted(result, operation);
    } catch (error) {
      if (widget.showDebugInfo) {
        debugPrint('Face verification capture failed: $error');
      }
      if (!_isCurrentOperation(operation)) return;
      _resetLiveness();
      final failure = _cameraFailure(error);
      _setState(() => _failure = failure);
      _notifyError(failure);
      await _ensureImageStream();
    } finally {
      if (file != null) await _deleteCapture(file.path);
      _setState(() => _busy = false);
      if (mounted && _appActive && !_reconfiguring && _camera == null) {
        unawaited(_initialize());
      } else if (_retryAfterOperation) {
        _retryAfterOperation = false;
        unawaited(_retry());
      }
    }
  }

  Future<void> _retry() async {
    if (_busy) {
      _retryAfterOperation = true;
      return;
    }
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
    return livenessGuidanceOrFallback(
      texts: widget.texts,
      session: _liveness,
      challengeComplete: _livenessComplete,
      fallback: widget.texts.lookStraight,
    );
  }

  String get _captureBlockReason {
    if (_busy) return 'processing';
    if (_result != null) return 'result available';
    if (!_livenessComplete) return 'complete liveness';
    final face = _face;
    if (face == null) return 'no single face';
    final quality = _kit?.evaluateQuality(face, verification: true);
    if (quality == null) return 'engine not ready';
    if (!quality.isAcceptable) return quality.issues.first;
    return 'READY';
  }

  String get _debugLabel {
    final face = _face;
    final liveness = _liveness;
    final faceLine = face == null
        ? 'face=no'
        : 'face=yes score=${face.score.toStringAsFixed(2)} '
              'size=${face.faceFraction.toStringAsFixed(2)} '
              'yaw=${_number(face.yaw)} pitch=${_number(face.pitch)}';
    final eyeLine = face == null
        ? 'eyes=--/--'
        : 'eyes=${_number(face.leftEyeOpenProbability)}/'
              '${_number(face.rightEyeOpenProbability)} '
              'roll=${_number(face.roll)}';
    final liveLine = liveness == null
        ? 'liveness=disabled'
        : 'live=${liveness.completedActions}/${liveness.totalActions} '
              '${liveness.currentAction?.name ?? 'done'} '
              'phase=${liveness.currentPhase.name} '
              'stable=${liveness.stableFrames} resets=${liveness.resetCount}';
    return '$faceLine\n$eyeLine\n$liveLine\nbutton=$_captureBlockReason';
  }

  String _number(double? value) => value?.toStringAsFixed(2) ?? '--';

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return ColoredBox(
      color: widget.theme.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 690;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, 12),
            child: camera == null || !camera.value.isInitialized
                ? Center(
                    child: Text(
                      _failure?.message ?? widget.texts.initializing,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _failure == null
                            ? widget.theme.foregroundColor
                            : widget.theme.errorColor,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      FaceFriendlyHeader(
                        title: widget.texts.verificationTitle,
                        accentColor: widget.theme.secondaryAccentColor,
                        theme: widget.theme,
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      FacePoseProgress(
                        activeIndex: _livenessComplete ? 2 : 1,
                        accentColor: widget.theme.secondaryAccentColor,
                        theme: widget.theme,
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: SizedBox.expand(
                              child: FaceCameraFrame(
                                controller: camera,
                                face: _face,
                                isReady:
                                    _captureReady ||
                                    (_result?.isMatch ?? false),
                                theme: widget.theme,
                                topOverlay: FaceCameraTitle(
                                  label: _failure?.message ?? _instruction,
                                ),
                                bottomOverlay: FaceCameraPill(
                                  label: _result?.isMatch ?? false
                                      ? widget.texts.success
                                      : _face != null
                                      ? widget.texts.faceReady
                                      : widget.texts.centerFace,
                                  icon: _result?.isMatch ?? false
                                      ? Icons.verified_rounded
                                      : _face != null
                                      ? Icons.check_rounded
                                      : Icons.face_rounded,
                                  accentColor:
                                      widget.theme.secondaryAccentColor,
                                ),
                                overlayBuilder: widget.overlayBuilder,
                                debugLabel: widget.showDebugInfo
                                    ? _debugLabel
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      if (_result == null)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor:
                                  widget.theme.secondaryAccentColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: widget
                                  .theme
                                  .secondaryAccentColor
                                  .withValues(alpha: 0.24),
                              disabledForegroundColor: widget
                                  .theme
                                  .foregroundColor
                                  .withValues(alpha: 0.58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: _captureReady ? _verify : null,
                            child: Semantics(
                              label: _busy
                                  ? widget.texts.processing
                                  : widget.texts.verify,
                              child: Icon(
                                _busy
                                    ? Icons.hourglass_top_rounded
                                    : Icons.center_focus_strong_rounded,
                                size: 30,
                              ),
                            ),
                          ),
                        )
                      else if (!_result!.isMatch)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              foregroundColor:
                                  widget.theme.secondaryAccentColor,
                              side: BorderSide(
                                color: widget.theme.secondaryAccentColor,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: _busy ? null : _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(widget.texts.retry),
                          ),
                        ),
                    ],
                  ),
          );
        },
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
    _operationGeneration++;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  bool _isCurrentInitialization(int generation) =>
      mounted && _appActive && generation == _initializationGeneration;

  bool _isCurrentOperation(int generation) =>
      mounted && _appActive && generation == _operationGeneration;

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

  void _notifyCompleted(VerificationResult result, int operation) {
    if (!_isCurrentOperation(operation)) return;
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

  void _notifyError(FaceMatchFailure failure) {
    if (!mounted) return;
    try {
      widget.onError?.call(failure);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'face_match_kit',
          context: ErrorDescription('while calling onError'),
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
    _operationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    if (_ownsKit) unawaited(_kit?.dispose());
    super.dispose();
  }
}

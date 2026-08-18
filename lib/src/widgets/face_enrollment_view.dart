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

class FaceEnrollmentView extends StatefulWidget {
  final FaceMatchKit? kit;
  final FaceMatchConfig config;
  final ValueChanged<EnrollmentResult> onCompleted;
  final ValueChanged<FaceMatchFailure>? onError;
  final FaceMatchTheme theme;
  final FaceMatchTexts texts;
  final FaceOverlayBuilder? overlayBuilder;
  final bool showDebugInfo;

  const FaceEnrollmentView({
    super.key,
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
  var _reconfiguring = false;
  var _appActive = true;
  var _initializationGeneration = 0;
  var _operationGeneration = 0;
  var _missingFaceFrames = 0;
  var _autoCaptureScheduled = false;
  DateTime? _livenessCompletedAt;

  FaceMatchConfig get _effectiveConfig => widget.kit?.config ?? widget.config;
  FacePose get _pose => FacePose.values[_samples.length.clamp(0, 2)];
  bool get _livenessExpired =>
      _samples.isEmpty &&
      _livenessCompletedAt != null &&
      DateTime.now().difference(_livenessCompletedAt!) >
          _effectiveConfig.livenessCompletionTimeout;
  bool get _livenessComplete =>
      !_effectiveConfig.livenessEnabled ||
      ((_liveness?.isComplete ?? false) && !_livenessExpired);
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

  @override
  void didUpdateWidget(covariant FaceEnrollmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final kitChanged = !identical(oldWidget.kit, widget.kit);
    final configChanged =
        widget.kit == null && oldWidget.config != widget.config;
    if (kitChanged || configChanged) unawaited(_reconfigure());
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
      _samples.clear();
      setStateIfMounted(() {
        _face = null;
        _failure = null;
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
        // CameraX exposes requested NV21 as one plane, while the detector's
        // camera converter expects Android YUV420 planes. Using NV21 here
        // therefore produced a silent stream of "no face" results.
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
      setStateIfMounted(() {});
    } catch (error) {
      if (identical(_camera, controller)) _camera = null;
      await controller?.dispose();
      controller = null;
      if (widget.showDebugInfo) {
        debugPrint('Face enrollment initialization failed: $error');
      }
      if (!_isCurrentInitialization(generation)) return;
      final failure = _cameraFailure(error, initialization: true);
      setStateIfMounted(() => _failure = failure);
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
      if (!mounted ||
          generation != _initializationGeneration ||
          !identical(camera, _camera)) {
        return;
      }
      final face = result.hasExactlyOneFace ? result.faces.single : null;
      var livenessJustCompleted = false;
      if (_livenessExpired) _resetLiveness();
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
          if (livenessJustCompleted) _livenessCompletedAt = DateTime.now();
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
    final operation = ++_operationGeneration;
    final camera = _camera!;
    final pose = _pose;
    setState(() => _busy = true);
    XFile? file;
    try {
      await camera.stopImageStream();
      file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      if (!_isCurrentOperation(operation)) return;
      _samples.add(FaceSample(imageBytes: bytes, pose: pose));
      _face = null;
      if (_samples.length == FacePose.values.length) {
        final result = await _kit!.enroll(samples: List.of(_samples));
        if (!_isCurrentOperation(operation)) return;
        _samples.clear();
        if (result.isSuccess) {
          _notifyCompleted(result, operation);
        } else {
          _failure = result.failure;
          _notifyError(result.failure!);
          _resetLiveness();
          await _ensureImageStream();
        }
      } else {
        await _ensureImageStream();
      }
    } catch (error) {
      if (widget.showDebugInfo) {
        debugPrint('Face enrollment capture failed: $error');
      }
      if (!_isCurrentOperation(operation)) return;
      _failure = _cameraFailure(error);
      _notifyError(_failure!);
      if (_samples.isEmpty) _resetLiveness();
      await _ensureImageStream();
    } finally {
      if (file != null) await _deleteCapture(file.path);
      setStateIfMounted(() => _busy = false);
      if (mounted && _appActive && !_reconfiguring && _camera == null) {
        unawaited(_initialize());
      }
    }
  }

  String get _instruction {
    if (!_livenessComplete) {
      return widget.texts.livenessStep(
        _liveness!.currentAction!,
        _liveness!.currentPhase,
      );
    }
    return widget.texts.pose(_pose);
  }

  String get _captureBlockReason {
    if (_busy) return 'processing';
    if (!_livenessComplete) return 'complete liveness';
    final face = _face;
    if (face == null) return 'no single face';
    if (!poseIsReady(_pose, face)) return 'pose ${_pose.name} not ready';
    final quality = _kit?.evaluateQuality(face);
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
                ? _Status(
                    message: _failure?.message ?? widget.texts.initializing,
                    color: _failure == null
                        ? widget.theme.foregroundColor
                        : widget.theme.errorColor,
                  )
                : Column(
                    children: [
                      FaceFriendlyHeader(
                        title: widget.texts.enrollmentTitle,
                        accentColor: widget.theme.accentColor,
                        theme: widget.theme,
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: SizedBox.expand(
                              child: FaceCameraFrame(
                                controller: camera,
                                face: _face,
                                isReady: _captureReady,
                                theme: widget.theme,
                                topOverlay: FacePoseProgress(
                                  activeIndex: _samples.length.clamp(0, 2),
                                  theme: widget.theme,
                                ),
                                bottomOverlay: FaceCameraPill(
                                  label: _failure?.message ?? _instruction,
                                  icon: _failure != null
                                      ? Icons.info_outline_rounded
                                      : guidanceIcon(
                                          failure: _failure,
                                          pose: _pose,
                                        ),
                                  accentColor: _failure != null
                                      ? widget.theme.errorColor
                                      : widget.theme.warningColor,
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
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: widget.theme.accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: widget.theme.accentColor
                                .withValues(alpha: 0.22),
                            disabledForegroundColor: widget
                                .theme
                                .foregroundColor
                                .withValues(alpha: 0.58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          onPressed: _captureReady ? _capture : null,
                          icon: Icon(
                            _captureReady
                                ? Icons.camera_alt_rounded
                                : Icons.face_rounded,
                          ),
                          label: Text(
                            _busy
                                ? widget.texts.processing
                                : _captureReady
                                ? widget.texts.capture
                                : _face == null
                                ? widget.texts.centerFace
                                : widget.texts.completeFaceCheck,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
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
    _operationGeneration++;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  bool _isCurrentInitialization(int generation) =>
      mounted && _appActive && generation == _initializationGeneration;

  bool _isCurrentOperation(int generation) =>
      mounted && _appActive && generation == _operationGeneration;

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

  void _notifyCompleted(EnrollmentResult result, int operation) {
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

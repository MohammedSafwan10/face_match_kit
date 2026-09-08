import 'dart:math';
import 'dart:developer' as developer;

import 'face_match_models.dart';

enum CaptureFlowPolicy {
  legacy,
  guidedEnrollment,
  singleTurnVerification,

  /// Easy employee check-in: one straight look, no left/right turns.
  /// Added because the turn-and-return flow confused users and failed on
  /// shaky phones; verification matches the enrolled centroid which already
  /// averages all three enrollment poses.
  simpleVerification,
}

/// Camera-independent state machine; timestamps are supplied for deterministic tests.
class CaptureFlow {
  final CaptureFlowPolicy policy;
  final Random random;
  late List<FacePose> poses;
  int step = 0;
  int resets = 0;
  int _frames = 0;
  DateTime? _started, _stable, _last, _completed;
  FaceBox? _box;
  bool ready = false;

  void record(String event, {String? reason}) {
    developer.log(
      'flow=${policy.name} event=$event step=$step resets=$resets reason=${reason ?? "none"}',
      name: 'face_capture',
    );
  }

  CaptureFlow(this.policy, {Random? random})
    : random = random ?? Random.secure() {
    reset();
  }

  void reset() {
    final sides = [FacePose.slightLeft, FacePose.slightRight]..shuffle(random);
    poses = switch (policy) {
      CaptureFlowPolicy.guidedEnrollment => [FacePose.front, ...sides],
      // One straight look only: no turns for employees.
      CaptureFlowPolicy.simpleVerification => const [FacePose.front],
      _ => [FacePose.front, sides.first, FacePose.front],
    };
    step = 0;
    resets++;
    _frames = 0;
    _started = _stable = _last = _completed = null;
    _box = null;
    ready = false;
  }

  FacePose get pose => poses[step.clamp(0, poses.length - 1)];
  bool get enrollment => policy == CaptureFlowPolicy.guidedEnrollment;

  static bool continuous(FaceBox? previous, FaceBox current) {
    bool valid(FaceBox b) =>
        [b.left, b.top, b.right, b.bottom].every((v) => v.isFinite) &&
        b.width > 0 &&
        b.height > 0;
    if (!valid(current)) return false;
    if (previous == null) return true;
    if (!valid(previous)) return false;
    final dx =
        (current.left + current.right - previous.left - previous.right) / 2;
    final dy =
        (current.top + current.bottom - previous.top - previous.bottom) / 2;
    final ratio = current.width / previous.width;
    return sqrt(dx * dx + dy * dy) <= previous.width * .65 &&
        ratio >= .55 &&
        ratio <= 1.8;
  }

  static bool matches(FacePose pose, double? yaw) {
    if (yaw == null || !yaw.isFinite) return false;
    // Live windows must match the still-enrollment gate in
    // FaceMatchKit._poseMatches (front ±12, sides 10-42) and the legacy
    // poseIsReady helper. A stricter live window (±8 / 15-35) left users
    // staring straight with yaw 9-12° stuck forever on step 1: live never
    // became ready even though the still capture would have accepted it.
    return switch (pose) {
      FacePose.front => yaw.abs() <= 12,
      FacePose.slightLeft => yaw >= 10 && yaw <= 42,
      FacePose.slightRight => yaw <= -10 && yaw >= -42,
    };
  }

  /// Returns true on invalidation so the view can erase captured samples.
  bool update(
    DetectedFace? face, {
    required bool multiple,
    required bool quality,
    required DateTime now,
  }) {
    final expired =
        _started != null &&
        now.difference(_started!) > const Duration(seconds: 30);
    // Gap tolerance must cover real on-device inference latency. Live frames
    // are processed serially in Dart (YUV->RGB conversion + YuNet + landmarks
    // + blendshapes, typically 300-800ms) plus liveDetectionInterval, and the
    // views timestamp AFTER `await detectCameraFrame`. A 500ms gap therefore
    // reset the flow on every frame on slower phones, so step 1 could never
    // accumulate the 3 stable frames / 300ms needed for `ready`.
    final gap =
        _last != null &&
        now.difference(_last!) > const Duration(milliseconds: 1500);
    final invalid =
        multiple ||
        expired ||
        gap ||
        (face != null && !continuous(_box, face.box)) ||
        (_completed != null &&
            now.difference(_completed!) > const Duration(seconds: 5));
    if (invalid) {
      record(
        'reset',
        reason: multiple
            ? 'multiple_faces'
            : expired
            ? 'deadline'
            : gap
            ? 'frame_gap'
            : 'continuity_or_expiry',
      );
      reset();
    }
    if (multiple || face == null || !continuous(null, face.box)) {
      _frames = 0;
      _stable = null;
      ready = false;
      return invalid;
    }
    _started ??= now;
    _last = now;
    _box = face.box;
    if (!quality || !matches(pose, face.yaw)) {
      _frames = 0;
      _stable = null;
      ready = false;
      return invalid;
    }
    _stable ??= now;
    _frames++;
    if (_frames >= 3 &&
        now.difference(_stable!) >= const Duration(milliseconds: 300)) {
      // Multi-stage verification walks poses; single-pose flows (simple
      // verification) become ready on the first stable front look.
      if (!enrollment && step < poses.length - 1) {
        step++;
        _frames = 0;
        _stable = null;
      } else {
        if (!ready) {
          developer.log(
            'flow=${policy.name} event=ready elapsed_ms=${now.difference(_started!).inMilliseconds}',
            name: 'face_capture',
          );
        }
        ready = true;
        if (!enrollment) _completed ??= now;
      }
    }
    return invalid;
  }

  void captured() {
    if (!enrollment || !ready) throw StateError('Capture was not ready');
    step++;
    ready = false;
    _frames = 0;
    _stable = null;
    // Intentional camera stream pause during still capture is not face loss.
    _last = null;
  }
}

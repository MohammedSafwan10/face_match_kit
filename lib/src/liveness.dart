import 'dart:math';

import 'face_match_models.dart';
import 'capture_flow.dart';

/// Basic challenge actions. These are not advanced anti-spoofing.
enum LivenessAction { blink, turnLeft, turnRight }

/// Current step within one liveness action.
enum LivenessPhase { neutral, action, returned }

class LivenessChallenge {
  final List<LivenessAction> actions;

  LivenessChallenge(List<LivenessAction> actions)
    : actions = List.unmodifiable(actions) {
    if (actions.isEmpty || actions.length > LivenessAction.values.length) {
      throw ArgumentError.value(
        actions,
        'actions',
        'A challenge requires between 1 and 3 actions.',
      );
    }
    if (actions.toSet().length != actions.length) {
      throw ArgumentError.value(
        actions,
        'actions',
        'Challenge actions must be distinct.',
      );
    }
  }

  factory LivenessChallenge.random({int actionCount = 2, Random? random}) {
    final generator = random ?? Random.secure();
    final values = [...LivenessAction.values]..shuffle(generator);
    return LivenessChallenge(values.take(actionCount.clamp(1, 3)).toList());
  }
}

class LivenessProgress {
  final bool isComplete;
  final int completedActions;
  final LivenessAction? currentAction;

  const LivenessProgress({
    required this.isComplete,
    required this.completedActions,
    required this.currentAction,
  });
}

/// Temporal state machine used by the camera widgets.
class LivenessSession {
  final LivenessChallenge challenge;
  final Duration actionTimeout;
  final DateTime Function() _now;
  int _index = 0;
  LivenessPhase _phase = LivenessPhase.neutral;
  int _stableFrames = 0;
  int _resetCount = 0;
  FaceBox? _previousBox;
  late DateTime _actionStartedAt;

  LivenessSession(
    this.challenge, {
    this.actionTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (actionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        actionTimeout,
        'actionTimeout',
        'Must be positive.',
      );
    }
    _actionStartedAt = _now();
  }

  bool get isComplete => _index >= challenge.actions.length;
  LivenessAction? get currentAction =>
      isComplete ? null : challenge.actions[_index];
  LivenessPhase get currentPhase => _phase;
  int get completedActions => _index;
  int get totalActions => challenge.actions.length;
  int get stableFrames => _stableFrames;
  int get resetCount => _resetCount;

  LivenessProgress update(DetectedFace face) {
    if (isComplete) return _progress();
    if (_now().difference(_actionStartedAt) > actionTimeout) reset();
    if (!_isContinuous(face.box)) {
      reset();
    }
    _previousBox = face.box;
    final action = currentAction!;
    final condition = _conditionFor(action, face, _phase);
    _stableFrames = condition ? _stableFrames + 1 : 0;
    const requiredFrames = 2;
    if (_stableFrames >= requiredFrames) {
      _stableFrames = 0;
      if (_phase == LivenessPhase.returned) {
        _index++;
        _phase = LivenessPhase.neutral;
        _actionStartedAt = _now();
      } else {
        _phase = LivenessPhase.values[_phase.index + 1];
      }
    }
    return _progress();
  }

  /// Restarts the complete challenge after face loss or timeout.
  void reset() {
    _index = 0;
    _phase = LivenessPhase.neutral;
    _stableFrames = 0;
    _previousBox = null;
    _resetCount++;
    _actionStartedAt = _now();
  }

  bool _isContinuous(FaceBox current) {
    return CaptureFlow.continuous(_previousBox, current);
  }

  bool _conditionFor(
    LivenessAction action,
    DetectedFace face,
    LivenessPhase phase,
  ) {
    switch (action) {
      case LivenessAction.blink:
        final left = face.leftEyeOpenProbability;
        final right = face.rightEyeOpenProbability;
        if (left == null || right == null) return false;
        final openness = (left + right) / 2;
        return switch (phase) {
          LivenessPhase.neutral || LivenessPhase.returned => openness >= 0.55,
          LivenessPhase.action => openness <= 0.45,
        };
      case LivenessAction.turnLeft:
        final yaw = face.yaw;
        if (yaw == null) return false;
        return switch (phase) {
          LivenessPhase.neutral || LivenessPhase.returned => yaw.abs() <= 12,
          // Detector yaw follows image coordinates. On a front-facing camera,
          // the user's left turn points toward the right side of the image.
          LivenessPhase.action => yaw >= 12,
        };
      case LivenessAction.turnRight:
        final yaw = face.yaw;
        if (yaw == null) return false;
        return switch (phase) {
          LivenessPhase.neutral || LivenessPhase.returned => yaw.abs() <= 12,
          LivenessPhase.action => yaw <= -12,
        };
    }
  }

  LivenessProgress _progress() => LivenessProgress(
    isComplete: isComplete,
    completedActions: _index,
    currentAction: currentAction,
  );
}

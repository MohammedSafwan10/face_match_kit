import 'dart:math';

import 'face_match_models.dart';

/// Basic challenge actions. These are not advanced anti-spoofing.
enum LivenessAction { blink, turnLeft, turnRight }

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
  _LivenessPhase _phase = _LivenessPhase.neutral;
  int _stableFrames = 0;
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

  LivenessProgress update(DetectedFace face) {
    if (isComplete) return _progress();
    if (_now().difference(_actionStartedAt) > actionTimeout) reset();
    final action = currentAction!;
    final condition = _conditionFor(action, face, _phase);
    _stableFrames = condition ? _stableFrames + 1 : 0;
    if (_stableFrames >= 2) {
      _stableFrames = 0;
      if (_phase == _LivenessPhase.returned) {
        _index++;
        _phase = _LivenessPhase.neutral;
        _actionStartedAt = _now();
      } else {
        _phase = _LivenessPhase.values[_phase.index + 1];
      }
    }
    return _progress();
  }

  /// Restarts the complete challenge after face loss or timeout.
  void reset() {
    _index = 0;
    _phase = _LivenessPhase.neutral;
    _stableFrames = 0;
    _actionStartedAt = _now();
  }

  bool _conditionFor(
    LivenessAction action,
    DetectedFace face,
    _LivenessPhase phase,
  ) {
    switch (action) {
      case LivenessAction.blink:
        final left = face.leftEyeOpenProbability;
        final right = face.rightEyeOpenProbability;
        if (left == null || right == null) return false;
        final openness = (left + right) / 2;
        return switch (phase) {
          _LivenessPhase.neutral || _LivenessPhase.returned => openness >= 0.62,
          _LivenessPhase.action => openness <= 0.35,
        };
      case LivenessAction.turnLeft:
        final yaw = face.yaw;
        if (yaw == null) return false;
        return switch (phase) {
          _LivenessPhase.neutral || _LivenessPhase.returned => yaw.abs() <= 8,
          _LivenessPhase.action => yaw <= -15,
        };
      case LivenessAction.turnRight:
        final yaw = face.yaw;
        if (yaw == null) return false;
        return switch (phase) {
          _LivenessPhase.neutral || _LivenessPhase.returned => yaw.abs() <= 8,
          _LivenessPhase.action => yaw >= 15,
        };
    }
  }

  LivenessProgress _progress() => LivenessProgress(
    isComplete: isComplete,
    completedActions: _index,
    currentAction: currentAction,
  );
}

enum _LivenessPhase { neutral, action, returned }

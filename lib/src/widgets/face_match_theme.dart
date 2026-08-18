import 'package:flutter/material.dart';

import '../face_match_models.dart';
import '../liveness.dart';

class FaceMatchTheme {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color accentColor;
  final Color secondaryAccentColor;
  final Color surfaceColor;
  final Color successColor;
  final Color warningColor;
  final Color errorColor;
  final Color overlayColor;
  final BorderRadius borderRadius;

  const FaceMatchTheme({
    this.backgroundColor = const Color(0xFFFFF9F2),
    this.foregroundColor = const Color(0xFF1D2028),
    this.accentColor = const Color(0xFFFF6B5F),
    this.secondaryAccentColor = const Color(0xFF9270DC),
    this.surfaceColor = Colors.white,
    this.successColor = const Color(0xFF7C5CE7),
    this.warningColor = const Color(0xFFF5B82E),
    this.errorColor = const Color(0xFFD94343),
    this.overlayColor = const Color(0x12000000),
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });
}

class FaceMatchTexts {
  final String initializing;
  final String permissionDenied;
  final String noCamera;
  final String capture;
  final String verify;
  final String retry;
  final String processing;
  final String success;
  final String lookStraight;
  final String cameraStartFailed;
  final String captureFailed;
  final String enrollmentRestarted;
  final String similarityLabel;
  final String enrollmentTitle;
  final String verificationTitle;
  final String faceReady;
  final String centerFace;
  final String completeFaceCheck;

  const FaceMatchTexts({
    this.initializing = 'Preparing secure face scan…',
    this.permissionDenied = 'Camera permission is required.',
    this.noCamera = 'No front camera is available.',
    this.capture = 'Take photo',
    this.verify = 'Verify',
    this.retry = 'Try again',
    this.processing = 'Processing on this device…',
    this.success = 'Face verified',
    this.lookStraight = 'Look straight at the camera',
    this.cameraStartFailed = 'Could not start the camera. Please try again.',
    this.captureFailed = 'Could not capture the image. Please try again.',
    this.enrollmentRestarted = 'Enrollment restarted. Please try again.',
    this.similarityLabel = 'Similarity',
    this.enrollmentTitle = "Let's set up your face",
    this.verificationTitle = 'Quick identity check',
    this.faceReady = 'Face ready',
    this.centerFace = 'Center your face',
    this.completeFaceCheck = 'Complete the face check',
  });

  String pose(FacePose pose) => switch (pose) {
    FacePose.front => 'Look straight at the camera',
    FacePose.slightLeft => 'Turn your head slightly left',
    FacePose.slightRight => 'Turn your head slightly right',
  };

  String liveness(LivenessAction action) => switch (action) {
    LivenessAction.blink => 'Blink once',
    LivenessAction.turnLeft => 'Turn your head left and back',
    LivenessAction.turnRight => 'Turn your head right and back',
  };

  String livenessStep(LivenessAction action, LivenessPhase phase) {
    if (phase == LivenessPhase.neutral) {
      return action == LivenessAction.blink
          ? 'Look straight and keep both eyes open'
          : 'Look straight to begin';
    }
    if (phase == LivenessPhase.returned) {
      return action == LivenessAction.blink
          ? 'Open both eyes'
          : 'Return your head to the center';
    }
    return switch (action) {
      LivenessAction.blink => 'Blink now',
      LivenessAction.turnLeft => 'Turn your head left',
      LivenessAction.turnRight => 'Turn your head right',
    };
  }

  String similarity(double value) =>
      '$similarityLabel ${(100 * value).toStringAsFixed(1)}%';
}

typedef FaceOverlayBuilder =
    Widget Function(BuildContext context, DetectedFace? face, bool isReady);

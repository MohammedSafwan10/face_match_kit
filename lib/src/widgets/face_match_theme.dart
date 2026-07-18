import 'package:flutter/material.dart';

import '../face_match_models.dart';
import '../liveness.dart';

class FaceMatchTheme {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color accentColor;
  final Color errorColor;
  final Color overlayColor;
  final BorderRadius borderRadius;

  const FaceMatchTheme({
    this.backgroundColor = const Color(0xFF0F172A),
    this.foregroundColor = Colors.white,
    this.accentColor = const Color(0xFF38BDF8),
    this.errorColor = const Color(0xFFF87171),
    this.overlayColor = const Color(0x66000000),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
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

  const FaceMatchTexts({
    this.initializing = 'Preparing secure face scan…',
    this.permissionDenied = 'Camera permission is required.',
    this.noCamera = 'No front camera is available.',
    this.capture = 'Capture',
    this.verify = 'Verify',
    this.retry = 'Try again',
    this.processing = 'Processing on this device…',
    this.success = 'Face verified',
    this.lookStraight = 'Look straight at the camera',
    this.cameraStartFailed = 'Could not start the camera. Please try again.',
    this.captureFailed = 'Could not capture the image. Please try again.',
    this.enrollmentRestarted = 'Enrollment restarted. Please try again.',
    this.similarityLabel = 'Similarity',
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

  String similarity(double value) =>
      '$similarityLabel ${(100 * value).toStringAsFixed(1)}%';
}

typedef FaceOverlayBuilder =
    Widget Function(BuildContext context, DetectedFace? face, bool isReady);

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../face_match_kit_base.dart';
import '../face_match_models.dart';

FaceCameraRotation rotationForCameraFrame({
  required int width,
  required int height,
  required int sensorOrientation,
  required bool isFrontCamera,
  required DeviceOrientation deviceOrientation,
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.iOS) {
    final isPortrait =
        deviceOrientation == DeviceOrientation.portraitUp ||
        deviceOrientation == DeviceOrientation.portraitDown;
    if (!isPortrait || height >= width) return FaceCameraRotation.none;
    return switch (sensorOrientation % 360) {
      90 => FaceCameraRotation.clockwise90,
      270 => FaceCameraRotation.clockwise270,
      _ => FaceCameraRotation.none,
    };
  }
  if (target != TargetPlatform.android) return FaceCameraRotation.none;

  final deviceRotation = switch (deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final total = isFrontCamera
      ? (sensorOrientation + deviceRotation) % 360
      : (sensorOrientation - deviceRotation + 360) % 360;
  return switch (total) {
    90 => FaceCameraRotation.clockwise90,
    180 => FaceCameraRotation.clockwise180,
    270 => FaceCameraRotation.clockwise270,
    _ => FaceCameraRotation.none,
  };
}

bool poseIsReady(FacePose pose, DetectedFace? face) {
  final yaw = face?.yaw;
  if (yaw == null) return false;
  return switch (pose) {
    FacePose.front => yaw >= -12 && yaw <= 12,
    FacePose.slightLeft => yaw >= -42 && yaw <= -10,
    FacePose.slightRight => yaw >= 10 && yaw <= 42,
  };
}

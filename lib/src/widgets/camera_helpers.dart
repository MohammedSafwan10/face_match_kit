import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../face_match_kit_base.dart';
import '../face_match_models.dart';

/// Camera stream format supported by the native frame conversion pipeline.
///
/// In particular, CameraX's one-plane NV21 stream is intentionally avoided;
/// the detector backend consumes Android's multi-plane YUV420 representation.
ImageFormatGroup cameraImageFormatForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? ImageFormatGroup.bgra8888
    : ImageFormatGroup.yuv420;

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
    // Public pose names describe the user's own direction, while detector yaw
    // uses image coordinates (the opposite horizontal direction for selfies).
    FacePose.slightLeft => yaw >= 10 && yaw <= 42,
    FacePose.slightRight => yaw >= -42 && yaw <= -10,
  };
}

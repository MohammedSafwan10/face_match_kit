import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Rotation applied to a live camera buffer before detection.
enum FaceCameraRotation { none, clockwise90, clockwise180, clockwise270 }

/// Pixel layouts accepted by [FaceCameraFrame].
enum FaceCameraPixelFormat { yuv420, bgra8888 }

/// One immutable image plane owned by a [FaceCameraFrame].
class FaceCameraPlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;

  FaceCameraPlane({
    required Uint8List bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  }) : bytes = Uint8List.fromList(bytes);
}

/// Package-owned live camera input.
///
/// Use [FaceCameraFrame.fromCameraImage] when integrating with Flutter's
/// `camera` plugin. The frame is copied so callers may release the original
/// camera buffer as soon as this constructor returns.
class FaceCameraFrame {
  final int width;
  final int height;
  final FaceCameraPixelFormat format;
  final FaceCameraRotation rotation;
  final bool mirrored;
  final List<FaceCameraPlane> planes;

  FaceCameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required List<FaceCameraPlane> planes,
    this.rotation = FaceCameraRotation.none,
    this.mirrored = false,
  }) : planes = List.unmodifiable(planes) {
    if (width <= 0 || height <= 0 || planes.isEmpty) {
      throw ArgumentError('Camera frame dimensions and planes are required.');
    }
    if (format == FaceCameraPixelFormat.yuv420 && planes.length < 3) {
      throw ArgumentError('YUV420 frames require Y, U, and V planes.');
    }
    if (format == FaceCameraPixelFormat.bgra8888 && planes.length != 1) {
      throw ArgumentError('BGRA8888 frames require exactly one plane.');
    }
    for (final plane in planes) {
      if (plane.bytesPerRow <= 0 ||
          plane.bytesPerPixel <= 0 ||
          plane.bytes.isEmpty) {
        throw ArgumentError('Camera plane strides and bytes are invalid.');
      }
    }
  }

  factory FaceCameraFrame.fromCameraImage(
    CameraImage image, {
    required FaceCameraRotation rotation,
    bool mirrored = false,
  }) {
    final format = switch (image.format.group) {
      ImageFormatGroup.bgra8888 => FaceCameraPixelFormat.bgra8888,
      ImageFormatGroup.yuv420 => FaceCameraPixelFormat.yuv420,
      _ => throw UnsupportedError(
        'Only BGRA8888 and three-plane YUV420 camera frames are supported.',
      ),
    };
    return FaceCameraFrame(
      width: image.width,
      height: image.height,
      format: format,
      rotation: rotation,
      mirrored: mirrored,
      planes: [
        for (final plane in image.planes)
          FaceCameraPlane(
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel ?? 1,
          ),
      ],
    );
  }
}

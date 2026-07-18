import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../face_match_models.dart';
import 'face_match_theme.dart';

class FaceCameraFrame extends StatelessWidget {
  final CameraController controller;
  final DetectedFace? face;
  final bool isReady;
  final FaceMatchTheme theme;
  final FaceOverlayBuilder? overlayBuilder;

  const FaceCameraFrame({
    super.key,
    required this.controller,
    required this.face,
    required this.isReady,
    required this.theme,
    this.overlayBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final orientation = controller.value.deviceOrientation;
    final isPortrait =
        orientation == DeviceOrientation.portraitUp ||
        orientation == DeviceOrientation.portraitDown;
    final previewAspectRatio = isPortrait
        ? 1 / controller.value.aspectRatio
        : controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: theme.borderRadius,
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),
            if (overlayBuilder != null)
              overlayBuilder!(context, face, isReady)
            else
              IgnorePointer(
                child: CustomPaint(
                  painter: _FaceGuidePainter(
                    color: isReady ? theme.accentColor : theme.foregroundColor,
                    overlay: theme.overlayColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final Color color;
  final Color overlay;

  const _FaceGuidePainter({required this.color, required this.overlay});

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.64,
      height: size.height * 0.72,
    );
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = overlay);
    canvas.drawOval(
      hole,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.overlay != overlay;
}

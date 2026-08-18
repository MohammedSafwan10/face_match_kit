import 'dart:math' as math;

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
  final Widget? topOverlay;
  final Widget? bottomOverlay;
  final FaceOverlayBuilder? overlayBuilder;
  final String? debugLabel;

  const FaceCameraFrame({
    super.key,
    required this.controller,
    required this.face,
    required this.isReady,
    required this.theme,
    this.topOverlay,
    this.bottomOverlay,
    this.overlayBuilder,
    this.debugLabel,
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: theme.borderRadius,
        color: const Color(0xFF202124),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: theme.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewAspectRatio * 1000,
                  height: 1000,
                  child: CameraPreview(controller),
                ),
              ),
            ),
            if (overlayBuilder != null)
              overlayBuilder!(context, face, isReady)
            else
              IgnorePointer(
                child: CustomPaint(
                  painter: _FaceGuidePainter(
                    color: isReady ? theme.successColor : Colors.white,
                    overlay: theme.overlayColor,
                  ),
                ),
              ),
            if (topOverlay != null)
              Positioned(left: 12, right: 12, top: 12, child: topOverlay!),
            if (bottomOverlay != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: bottomOverlay!,
              ),
            if (debugLabel != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC020617),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x5538BDF8)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        debugLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.25,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
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
    final guideWidth = math.min(size.width * 0.64, 236.0);
    final guideHeight = math.min(guideWidth * 1.34, size.height * 0.76);
    final hole = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: guideWidth,
      height: guideHeight,
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
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.overlay != overlay;
}

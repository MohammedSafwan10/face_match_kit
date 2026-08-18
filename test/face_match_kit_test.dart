import 'dart:math';

import 'package:face_match_kit/face_match_kit.dart';
import 'package:face_match_kit/src/image_normalizer.dart';
import 'package:face_match_kit/src/widgets/camera_helpers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  List<double> unitEmbedding(int phase) {
    final raw = [
      for (var index = 0; index < FaceMatchKit.embeddingDimensions; index++)
        sin((index + 1) * (phase + 1)) + 0.25 * cos(index + phase + 1),
    ];
    return normalizedCentroid([raw]);
  }

  FaceTemplate template({List<double>? centroid}) {
    final samples = {
      for (final pose in FacePose.values) pose: unitEmbedding(pose.index + 1),
    };
    return FaceTemplate(
      modelId: FaceMatchKit.modelId,
      modelHash: FaceMatchKit.modelHash,
      pipelineVersion: FaceMatchKit.pipelineVersion,
      dimensions: FaceMatchKit.embeddingDimensions,
      samples: samples,
      centroid: centroid ?? normalizedCentroid(samples.values),
      createdAt: DateTime.utc(2026, 7, 18),
    );
  }

  group('FaceTemplate', () {
    test('round trips all versioned fields', () {
      final original = template();
      final restored = FaceTemplate.fromJson(original.toJson());

      expect(restored.modelHash, original.modelHash);
      expect(restored.pipelineVersion, original.pipelineVersion);
      expect(
        restored.samples[FacePose.slightLeft],
        original.samples[FacePose.slightLeft],
      );
      expect(restored.centroid.length, FaceMatchKit.embeddingDimensions);
    });

    test('rejects legacy or incomplete templates', () {
      expect(
        () => FaceTemplate.fromJson({
          'schemaVersion': 0,
          'modelId': 'legacy',
          'modelHash': 'unknown',
          'pipelineVersion': 'legacy',
          'dimensions': 192,
          'samples': const {},
          'centroid': List<double>.filled(192, 0),
          'createdAt': DateTime.now().toIso8601String(),
        }),
        throwsFormatException,
      );
    });

    test('rejects fractional fields and unknown pose keys', () {
      final json = template().toJson();
      expect(
        () => FaceTemplate.fromJson({...json, 'schemaVersion': 1.2}),
        throwsFormatException,
      );
      final samples = Map<String, dynamic>.from(json['samples'] as Map)
        ..['unexpected'] = unitEmbedding(10);
      expect(
        () => FaceTemplate.fromJson({...json, 'samples': samples}),
        throwsFormatException,
      );
    });

    test('rejects non-unit samples and a tampered centroid', () {
      final json = template().toJson();
      final samples = Map<String, dynamic>.from(json['samples'] as Map)
        ..['front'] = List<double>.filled(FaceMatchKit.embeddingDimensions, 0);
      expect(
        () => FaceTemplate.fromJson({...json, 'samples': samples}),
        throwsFormatException,
      );
      expect(
        () => template(centroid: unitEmbedding(30)),
        throwsFormatException,
      );
    });

    test('rejects oversized serialized dimensions before copying lists', () {
      expect(
        () => FaceTemplate.fromJson({
          'schemaVersion': FaceTemplate.currentSchemaVersion,
          'modelId': FaceMatchKit.modelId,
          'modelHash': FaceMatchKit.modelHash,
          'pipelineVersion': FaceMatchKit.pipelineVersion,
          'dimensions': FaceTemplate.maximumSerializedDimensions + 1,
          'samples': const {},
          'centroid': const [],
          'createdAt': DateTime.now().toIso8601String(),
        }),
        throwsFormatException,
      );
    });
  });

  group('configuration', () {
    test('uses value equality for safe widget reconfiguration', () {
      expect(const FaceMatchConfig(), const FaceMatchConfig());
      expect(
        const FaceMatchConfig(livenessEnabled: false),
        isNot(const FaceMatchConfig()),
      );
    });

    test('rejects invalid values in release-safe validation', () {
      expect(
        () =>
            const FaceMatchConfig(verificationThreshold: double.nan).validate(),
        throwsArgumentError,
      );
      expect(
        () => const FaceMatchConfig(livenessFaceLossTolerance: 0).validate(),
        throwsArgumentError,
      );
    });
  });

  group('embedding math', () {
    test('cosine similarity distinguishes equal and opposite vectors', () {
      expect(cosineSimilarity([1, 0], [1, 0]), closeTo(1, 1e-12));
      expect(cosineSimilarity([1, 0], [-1, 0]), closeTo(-1, 1e-12));
    });

    test('centroid is L2 normalized', () {
      final centroid = normalizedCentroid([
        [1, 0],
        [0, 1],
      ]);
      final norm = sqrt(centroid.fold<double>(0, (sum, v) => sum + v * v));
      expect(norm, closeTo(1, 1e-12));
    });

    test('minimum pairwise score detects inconsistent enrollment', () {
      expect(
        minimumPairwiseSimilarity([
          [1, 0],
          [0.9, sqrt(0.19)],
          [-1, 0],
        ]),
        closeTo(-1, 1e-12),
      );
    });
  });

  test('canonicalization removes mirroring without JPEG loss', () async {
    final source = image.Image(width: 20, height: 10);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x < 10 ? 255 : 0, 0, x < 10 ? 0 : 255);
      }
    }
    final canonical = await canonicalizeImage(
      image.encodePng(source),
      mirrored: true,
    );
    final decoded = image.decodePng(canonical)!;

    expect(decoded.getPixel(2, 5).b, 255);
    expect(decoded.getPixel(17, 5).r, 255);
  });

  group('camera rotation', () {
    test('camera stream formats remain compatible with frame conversion', () {
      expect(
        cameraImageFormatForPlatform(TargetPlatform.android),
        ImageFormatGroup.yuv420,
      );
      expect(
        cameraImageFormatForPlatform(TargetPlatform.iOS),
        ImageFormatGroup.bgra8888,
      );
    });

    test('Android includes sensor, lens, and device orientation', () {
      expect(
        rotationForCameraFrame(
          width: 1280,
          height: 720,
          sensorOrientation: 270,
          isFrontCamera: true,
          deviceOrientation: DeviceOrientation.landscapeLeft,
          platform: TargetPlatform.android,
        ),
        FaceCameraRotation.none,
      );
      expect(
        rotationForCameraFrame(
          width: 1280,
          height: 720,
          sensorOrientation: 90,
          isFrontCamera: false,
          deviceOrientation: DeviceOrientation.landscapeRight,
          platform: TargetPlatform.android,
        ),
        FaceCameraRotation.clockwise180,
      );
    });

    test('iOS avoids rotating already-upright portrait frames', () {
      expect(
        rotationForCameraFrame(
          width: 720,
          height: 1280,
          sensorOrientation: 90,
          isFrontCamera: true,
          deviceOrientation: DeviceOrientation.portraitUp,
          platform: TargetPlatform.iOS,
        ),
        FaceCameraRotation.none,
      );
    });

    test('pose directions describe the selfie user, not image coordinates', () {
      DetectedFace face(double yaw) => DetectedFace(
        box: const FaceBox(left: 0, top: 0, right: 100, bottom: 100),
        score: 1,
        faceFraction: 0.5,
        yaw: yaw,
      );

      expect(poseIsReady(FacePose.slightLeft, face(20)), isTrue);
      expect(poseIsReady(FacePose.slightLeft, face(-20)), isFalse);
      expect(poseIsReady(FacePose.slightRight, face(-20)), isTrue);
      expect(poseIsReady(FacePose.slightRight, face(20)), isFalse);
    });
  });

  group('basic liveness', () {
    DetectedFace face({double? yaw, double? eyes}) => DetectedFace(
      box: const FaceBox(left: 0, top: 0, right: 100, bottom: 100),
      score: 1,
      faceFraction: 0.5,
      pitch: 0,
      roll: 0,
      yaw: yaw,
      leftEyeOpenProbability: eyes,
      rightEyeOpenProbability: eyes,
    );

    void twice(LivenessSession session, DetectedFace value) {
      session.update(value);
      session.update(value);
    }

    test('blink accepts one closed frame between stable open phases', () {
      final session = LivenessSession(
        LivenessChallenge([LivenessAction.blink]),
      );
      twice(session, face(eyes: 0.9));
      expect(session.currentPhase, LivenessPhase.action);
      session.update(face(eyes: 0.1));
      expect(session.currentPhase, LivenessPhase.returned);
      expect(session.isComplete, isFalse);
      twice(session, face(eyes: 0.9));
      expect(session.isComplete, isTrue);
    });

    test('head turn requires neutral, action, and return', () {
      final session = LivenessSession(
        LivenessChallenge([LivenessAction.turnLeft]),
      );
      twice(session, face(yaw: -20));
      expect(session.isComplete, isFalse);
      twice(session, face(yaw: 0));
      session.update(face(yaw: 20));
      expect(session.isComplete, isFalse);
      twice(session, face(yaw: 0));
      expect(session.isComplete, isTrue);
    });

    test('timeout restarts the complete challenge', () {
      var now = DateTime.utc(2026, 7, 18);
      final session = LivenessSession(
        LivenessChallenge([LivenessAction.blink]),
        actionTimeout: const Duration(seconds: 2),
        now: () => now,
      );
      session.update(face(eyes: 0.9));
      now = now.add(const Duration(seconds: 3));
      session.update(face(eyes: 0.1));
      twice(session, face(eyes: 0.9));
      expect(session.isComplete, isFalse);
    });

    test('challenge rejects duplicate actions', () {
      expect(
        () => LivenessChallenge([LivenessAction.blink, LivenessAction.blink]),
        throwsArgumentError,
      );
    });
  });
}

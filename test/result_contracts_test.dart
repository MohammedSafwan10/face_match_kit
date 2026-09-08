import 'dart:math';

import 'package:face_match_kit/src/face_match_models.dart';
import 'package:face_match_kit/src/face_pipeline_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for result/math invariants behind enroll/verify:
/// failure typing, template validation, and similarity edge cases.
/// Pure-Dart (no native engine) so they run without camera/FFI.
void main() {
  List<double> unit(List<double> raw) => normalizedCentroid([raw]);

  List<double> phaseEmbedding(int phase) {
    final raw = [
      for (var i = 0; i < FacePipelineIdentity.dimensions; i++)
        sin((i + 1) * (phase + 1)) + 0.25 * cos(i + phase + 1),
    ];
    return unit(raw);
  }

  Map<FacePose, List<double>> allPoses() => {
        for (final pose in FacePose.values) pose: phaseEmbedding(pose.index + 1),
      };

  FaceTemplate validTemplate({
    String? templateId,
    String? modelHash,
    int? dimensions,
    Map<FacePose, List<double>>? samples,
  }) {
    final s = samples ?? allPoses();
    return FaceTemplate(
      templateId: templateId ?? '00112233445566778899aabbccddeeff',
      modelId: FacePipelineIdentity.modelId,
      modelHash: modelHash ?? FacePipelineIdentity.modelHash,
      pipelineVersion: FacePipelineIdentity.pipelineVersion,
      dimensions: dimensions ?? FacePipelineIdentity.dimensions,
      samples: s,
      centroid: normalizedCentroid(s.values),
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  group('cosineSimilarity guards', () {
    test('identical embeddings score 1.0', () {
      final a = phaseEmbedding(1);
      expect(cosineSimilarity(a, List.of(a)), closeTo(1.0, 1e-9));
    });

    test('rejects NaN input instead of returning NaN', () {
      final a = phaseEmbedding(1);
      final bad = List.of(a)..[0] = double.nan;
      expect(() => cosineSimilarity(a, bad), throwsArgumentError);
      expect(() => cosineSimilarity(bad, a), throwsArgumentError);
    });

    test('rejects infinite input', () {
      final a = phaseEmbedding(1);
      final bad = List.of(a)..[1] = double.infinity;
      expect(() => cosineSimilarity(a, bad), throwsArgumentError);
    });

    test('rejects dimension mismatch', () {
      expect(
        () => cosineSimilarity(phaseEmbedding(1), [0.5, 0.5]),
        throwsArgumentError,
      );
    });
  });

  group('EnrollmentResult', () {
    test('success carries template, isSuccess true', () {
      final t = validTemplate();
      final r = EnrollmentResult.success(t);
      expect(r.isSuccess, isTrue);
      expect(r.template, same(t));
      expect(r.failure, isNull);
    });

    test('failure carries typed failure, isSuccess false', () {
      const f = FaceMatchFailure(FaceMatchErrorCode.noFace, 'no face');
      const r = EnrollmentResult.failure(f);
      expect(r.isSuccess, isFalse);
      expect(r.template, isNull);
      expect(r.failure, same(f));
    });
  });

  group('VerificationResult', () {
    test('below-threshold shape is explicit', () {
      const r = VerificationResult(
        isMatch: false,
        similarity: 0.42,
        threshold: 0.65,
      );
      expect(r.isMatch, isFalse);
      expect(r.similarity < r.threshold, isTrue);
      expect(r.failure, isNull);
    });
  });

  group('FaceTemplate validation', () {
    test('rejects malformed template id', () {
      expect(() => validTemplate(templateId: 'xyz'), throwsFormatException);
    });

    test('rejects malformed model hash', () {
      expect(() => validTemplate(modelHash: '00'), throwsFormatException);
    });

    test('rejects centroid/dimension mismatch', () {
      expect(
        () => validTemplate(dimensions: FacePipelineIdentity.dimensions + 1),
        throwsFormatException,
      );
    });

    test('rejects template from a different pipeline', () {
      final samples = allPoses();
      expect(
        () => FaceTemplate(
          templateId: '00112233445566778899aabbccddeeff',
          modelId: 'other-model',
          modelHash: FacePipelineIdentity.modelHash,
          pipelineVersion: FacePipelineIdentity.pipelineVersion,
          dimensions: FacePipelineIdentity.dimensions,
          samples: samples,
          centroid: normalizedCentroid(samples.values),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        throwsFormatException,
      );
    });
  });
}

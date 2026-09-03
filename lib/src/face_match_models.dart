import 'dart:math' as math;
import 'dart:typed_data';

import 'face_pipeline_identity.dart';

/// Stable identifiers for routine face-processing failures.
enum FaceMatchErrorCode {
  invalidImage,
  noFace,
  multipleFaces,
  lowQuality,
  wrongPose,
  invalidSampleSet,
  inconsistentEnrollment,
  incompatibleTemplate,
  belowThreshold,
  livenessFailed,
  permissionDenied,
  cameraUnavailable,
  cameraFailure,
  processingFailure,
  operationTimeout,
  frameDropped,
}

/// A typed, user-recoverable failure.
class FaceMatchFailure {
  final FaceMatchErrorCode code;
  final String message;

  const FaceMatchFailure(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

/// Bounding box normalized to the analyzed image, where each edge is 0 through 1.
class FaceBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const FaceBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// Package-owned face information returned by detection.
class DetectedFace {
  final FaceBox box;
  final double score;
  final double faceFraction;
  final double? pitch;
  final double? yaw;
  final double? roll;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  const DetectedFace({
    required this.box,
    required this.score,
    required this.faceFraction,
    this.pitch,
    this.yaw,
    this.roll,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
  });
}

/// Stable, localizable face-quality guidance.
enum FaceQualityIssue {
  betterLighting,
  moveCloser,
  landmarksUnavailable,
  keepLevel,
  straightenHead,
  lookStraight,
}

String faceQualityIssueMessage(FaceQualityIssue issue) => switch (issue) {
  FaceQualityIssue.betterLighting => 'Move into better lighting.',
  FaceQualityIssue.moveCloser => 'Move closer to the camera.',
  FaceQualityIssue.landmarksUnavailable =>
    'Hold still while facial landmarks are measured.',
  FaceQualityIssue.keepLevel => 'Keep your face level.',
  FaceQualityIssue.straightenHead => 'Straighten your head.',
  FaceQualityIssue.lookStraight => 'Look straight at the camera.',
};

/// Quality decision for a detected face.
class FaceQuality {
  final bool isAcceptable;
  final List<FaceQualityIssue> issues;

  const FaceQuality({required this.isAcceptable, required this.issues});

  const FaceQuality.acceptable() : isAcceptable = true, issues = const [];
}

/// Result of face detection. Routine failures do not throw.
class FaceDetectionResult {
  final List<DetectedFace> faces;
  final FaceQuality? quality;
  final FaceMatchFailure? failure;

  const FaceDetectionResult({
    this.faces = const [],
    this.quality,
    this.failure,
  });

  bool get isSuccess => failure == null;
  bool get hasExactlyOneFace => faces.length == 1;
}

/// Required enrollment poses.
enum FacePose { front, slightLeft, slightRight }

/// Encoded image bytes and their expected enrollment pose.
class FaceSample {
  final Uint8List imageBytes;
  final FacePose pose;

  /// Set only when the encoded pixels themselves are horizontally mirrored.
  /// A mirrored preview does not imply a mirrored captured file.
  final bool mirrored;

  const FaceSample({
    required this.imageBytes,
    required this.pose,
    this.mirrored = false,
  });
}

/// Versioned and portable biometric template.
class FaceTemplate {
  static const int currentSchemaVersion = FacePipelineIdentity.schemaVersion;
  static const int maximumSerializedDimensions =
      FacePipelineIdentity.dimensions;

  final int schemaVersion;
  final String templateId;
  final String modelId;
  final String modelHash;
  final String pipelineVersion;
  final int dimensions;
  final Map<FacePose, List<double>> samples;
  final List<double> centroid;
  final DateTime createdAt;

  FaceTemplate({
    this.schemaVersion = currentSchemaVersion,
    required this.templateId,
    required this.modelId,
    required this.modelHash,
    required this.pipelineVersion,
    required this.dimensions,
    required Map<FacePose, List<double>> samples,
    required List<double> centroid,
    required this.createdAt,
  }) : samples = Map.unmodifiable({
         for (final entry in samples.entries)
           entry.key: List<double>.unmodifiable(entry.value),
       }),
       centroid = List<double>.unmodifiable(centroid) {
    _validateShape();
  }

  void _validateShape() {
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported face template schema $schemaVersion.');
    }
    if (dimensions <= 0 || centroid.length != dimensions) {
      throw const FormatException('Invalid face template dimensions.');
    }
    if (modelId.trim().isEmpty || pipelineVersion.trim().isEmpty) {
      throw const FormatException(
        'Model and pipeline identifiers are required.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(templateId)) {
      throw const FormatException(
        'Template ID must be a lowercase 128-bit hexadecimal value.',
      );
    }
    if (modelId != FacePipelineIdentity.modelId ||
        modelHash != FacePipelineIdentity.modelHash ||
        pipelineVersion != FacePipelineIdentity.pipelineVersion ||
        dimensions != FacePipelineIdentity.dimensions) {
      throw const FormatException(
        'Face template uses an incompatible model or pipeline.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(modelHash)) {
      throw const FormatException('Model hash must be a lowercase SHA-256.');
    }
    if (samples.length != FacePose.values.length ||
        !FacePose.values.every(samples.containsKey)) {
      throw const FormatException('A face template requires all three poses.');
    }
    for (final embedding in samples.values) {
      if (embedding.length != dimensions ||
          embedding.any((value) => !value.isFinite)) {
        throw const FormatException('Invalid sample embedding.');
      }
      _requireUnitEmbedding(embedding, 'sample');
    }
    if (centroid.any((value) => !value.isFinite)) {
      throw const FormatException('Invalid centroid embedding.');
    }
    _requireUnitEmbedding(centroid, 'centroid');
    final expectedCentroid = normalizedCentroid(samples.values);
    for (var index = 0; index < dimensions; index++) {
      if ((centroid[index] - expectedCentroid[index]).abs() > 1e-5) {
        throw const FormatException(
          'Template centroid does not match its sample embeddings.',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'templateId': templateId,
    'modelId': modelId,
    'modelHash': modelHash,
    'pipelineVersion': pipelineVersion,
    'dimensions': dimensions,
    'samples': {
      for (final entry in samples.entries) entry.key.name: entry.value,
    },
    'centroid': centroid,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory FaceTemplate.fromJson(Map<String, dynamic> json) {
    try {
      const expectedKeys = <String>{
        'schemaVersion',
        'templateId',
        'modelId',
        'modelHash',
        'pipelineVersion',
        'dimensions',
        'samples',
        'centroid',
        'createdAt',
      };
      if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
          expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
        throw const FormatException('Face template fields are invalid.');
      }
      final dimensions = _strictInteger(json['dimensions'], 'dimensions');
      if (dimensions <= 0 || dimensions > maximumSerializedDimensions) {
        throw const FormatException('Invalid face template dimensions.');
      }
      final rawSamples = Map<String, dynamic>.from(json['samples'] as Map);
      final expectedPoseKeys = FacePose.values.map((pose) => pose.name).toSet();
      if (rawSamples.keys.toSet().difference(expectedPoseKeys).isNotEmpty ||
          expectedPoseKeys.difference(rawSamples.keys.toSet()).isNotEmpty) {
        throw const FormatException(
          'Template samples must contain exactly front, slightLeft, and '
          'slightRight.',
        );
      }
      for (final value in rawSamples.values) {
        if (value is! List || value.length != dimensions) {
          throw const FormatException('Invalid sample embedding dimensions.');
        }
      }
      final rawCentroid = json['centroid'];
      if (rawCentroid is! List || rawCentroid.length != dimensions) {
        throw const FormatException('Invalid centroid embedding dimensions.');
      }
      return FaceTemplate(
        schemaVersion: _strictInteger(json['schemaVersion'], 'schemaVersion'),
        templateId: json['templateId'] as String,
        modelId: json['modelId'] as String,
        modelHash: json['modelHash'] as String,
        pipelineVersion: json['pipelineVersion'] as String,
        dimensions: dimensions,
        samples: {
          for (final pose in FacePose.values)
            pose: (rawSamples[pose.name] as List)
                .map((value) => (value as num).toDouble())
                .toList(),
        },
        centroid: rawCentroid
            .map((value) => (value as num).toDouble())
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
    } catch (error) {
      if (error is FormatException) {
        rethrow;
      }
      throw FormatException('Malformed face template: $error');
    }
  }
}

/// Successful or failed enrollment result.
class EnrollmentResult {
  final FaceTemplate? template;
  final FaceMatchFailure? failure;

  const EnrollmentResult.success(FaceTemplate value)
    : template = value,
      failure = null;
  const EnrollmentResult.failure(FaceMatchFailure value)
    : failure = value,
      template = null;

  bool get isSuccess => template != null && failure == null;
}

/// 1:1 verification result.
class VerificationResult {
  final bool isMatch;
  final double similarity;
  final double threshold;
  final Map<FacePose, double> sampleSimilarities;
  final FaceMatchFailure? failure;

  const VerificationResult({
    required this.isMatch,
    required this.similarity,
    required this.threshold,
    this.sampleSimilarities = const {},
    this.failure,
  });
}

List<double> normalizedCentroid(Iterable<List<double>> embeddings) {
  final values = embeddings.toList(growable: false);
  if (values.isEmpty) {
    throw ArgumentError('At least one embedding is required.');
  }
  final dimensions = values.first.length;
  if (dimensions == 0 ||
      values.any(
        (item) =>
            item.length != dimensions || item.any((value) => !value.isFinite),
      )) {
    throw ArgumentError('Embedding dimensions must match.');
  }
  final centroid = List<double>.filled(dimensions, 0);
  for (final embedding in values) {
    for (var index = 0; index < dimensions; index++) {
      centroid[index] += embedding[index];
    }
  }
  final norm = math.sqrt(
    centroid.fold<double>(0, (sum, value) => sum + value * value),
  );
  if (norm == 0) throw ArgumentError('Cannot normalize a zero embedding.');
  return [for (final value in centroid) value / norm];
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) {
    throw ArgumentError('Embedding dimensions must match.');
  }
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var index = 0; index < a.length; index++) {
    dot += a[index] * b[index];
    normA += a[index] * a[index];
    normB += b[index] * b[index];
  }
  if (normA == 0 || normB == 0) return 0;
  return (dot / math.sqrt(normA * normB)).clamp(-1.0, 1.0);
}

double minimumPairwiseSimilarity(Iterable<List<double>> embeddings) {
  final values = embeddings.toList(growable: false);
  if (values.length < 2) {
    throw ArgumentError('At least two embeddings are required.');
  }
  var minimum = 1.0;
  for (var first = 0; first < values.length; first++) {
    for (var second = first + 1; second < values.length; second++) {
      minimum = math.min(
        minimum,
        cosineSimilarity(values[first], values[second]),
      );
    }
  }
  return minimum;
}

int _strictInteger(Object? value, String field) {
  if (value is! int) {
    throw FormatException('$field must be an integer.');
  }
  return value;
}

void _requireUnitEmbedding(List<double> embedding, String name) {
  final squaredNorm = embedding.fold<double>(
    0,
    (sum, value) => sum + value * value,
  );
  if (!squaredNorm.isFinite || (math.sqrt(squaredNorm) - 1).abs() > 5e-3) {
    throw FormatException('$name embedding must be L2-normalized.');
  }
}

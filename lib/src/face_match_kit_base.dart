import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'engine/face_engine.dart';
import 'face_camera_input.dart';
import 'face_match_config.dart';
import 'face_match_models.dart';
import 'face_pipeline_identity.dart';

/// On-device face detector, enrollment engine, and 1:1 verifier.
class FaceMatchKit {
  static const String modelId = FacePipelineIdentity.modelId;
  static const String modelHash = FacePipelineIdentity.modelHash;
  static const String pipelineVersion = FacePipelineIdentity.pipelineVersion;
  static const int embeddingDimensions = FacePipelineIdentity.dimensions;

  static const Map<String, String> _assetHashes = {
    'face_detection_yunet_2023mar.onnx':
        '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
    'face_recognition_sface_2021dec_int8.onnx': modelHash,
    'face_landmarks_detector.tflite':
        'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5',
    'face_blendshapes.tflite':
        '4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082',
  };

  final FaceMatchConfig config;
  final FaceEngine _engine;
  final String _temporarySfacePath;
  bool _disposed = false;
  int _activeOperations = 0;
  Completer<void>? _idleCompleter;

  FaceMatchKit._(this.config, this._engine, this._temporarySfacePath);

  /// Loads and verifies all bundled models and starts the native worker.
  static Future<FaceMatchKit> create({
    FaceMatchConfig config = const FaceMatchConfig(),
  }) async {
    config.validate();
    final assets = <String, Uint8List>{};
    for (final entry in _assetHashes.entries) {
      final data = await rootBundle.load(
        'packages/face_match_kit/assets/models/${entry.key}',
      );
      final bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final actual = sha256.convert(bytes).toString();
      if (actual != entry.value) {
        throw StateError('Face model integrity check failed for ${entry.key}.');
      }
      assets[entry.key] = bytes;
    }

    final random = math.Random.secure();
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final sfaceFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'face_match_kit_sface_$suffix.onnx',
    );
    try {
      await sfaceFile.writeAsBytes(
        assets['face_recognition_sface_2021dec_int8.onnx']!,
        flush: true,
      );
      final engine = await FaceEngine.create(
        yunet: assets['face_detection_yunet_2023mar.onnx']!,
        landmarks: assets['face_landmarks_detector.tflite']!,
        blendshapes: assets['face_blendshapes.tflite']!,
        sfacePath: sfaceFile.path,
        maximumInputBytes: config.maximumInputBytes,
        maximumImagePixels: config.maximumImagePixels,
        canonicalMaxDimension: config.canonicalMaxDimension,
      );
      return FaceMatchKit._(config, engine, sfaceFile.path);
    } catch (_) {
      await _deleteTemporaryFile(sfaceFile.path);
      rethrow;
    }
  }

  /// Detects faces in encoded JPEG/PNG bytes using the canonical pipeline.
  Future<FaceDetectionResult> detect(
    Uint8List imageBytes, {
    bool mirrored = false,
  }) => _runStill(() async {
    try {
      final result = await _engine
          .analyzeStill(imageBytes, mirrored: mirrored, embedding: false)
          .timeout(config.stillProcessingTimeout);
      return _publicDetection(result);
    } on TimeoutException {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.operationTimeout,
          'Face detection timed out.',
        ),
      );
    } on FormatException {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.invalidImage,
          'The image is malformed or exceeds the configured limits.',
        ),
      );
    } catch (_) {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Face detection could not be completed.',
        ),
      );
    }
  });

  /// Processes a package-owned camera frame for guidance and basic liveness.
  ///
  /// When live work is backed up, an older queued frame is dropped in favour
  /// of the newest one. Enrollment and verification use encoded still images.
  Future<FaceDetectionResult> detectCameraFrame(FaceCameraFrame frame) =>
      _runLive(() async {
        try {
          final result = await _engine
              .analyzeLive(frame)
              .timeout(config.liveDetectionTimeout);
          if (result == null) {
            return const FaceDetectionResult(
              failure: FaceMatchFailure(
                FaceMatchErrorCode.frameDropped,
                'A newer camera frame replaced this frame.',
              ),
            );
          }
          return _publicDetection(result);
        } on TimeoutException {
          return const FaceDetectionResult(
            failure: FaceMatchFailure(
              FaceMatchErrorCode.operationTimeout,
              'Live face detection timed out.',
            ),
          );
        } catch (_) {
          return const FaceDetectionResult(
            failure: FaceMatchFailure(
              FaceMatchErrorCode.processingFailure,
              'Live face detection could not be completed.',
            ),
          );
        }
      });

  /// Creates a schema-v2 template from front, slight-left, and slight-right.
  Future<EnrollmentResult> enroll({required List<FaceSample> samples}) =>
      _runStill(() => _enroll(samples));

  Future<EnrollmentResult> _enroll(List<FaceSample> samples) async {
    final byPose = <FacePose, FaceSample>{
      for (final sample in samples) sample.pose: sample,
    };
    if (samples.length != FacePose.values.length ||
        byPose.length != FacePose.values.length) {
      return const EnrollmentResult.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.invalidSampleSet,
          'Enrollment requires one front, left, and right sample.',
        ),
      );
    }

    final embeddings = <FacePose, List<double>>{};
    for (final pose in FacePose.values) {
      final sample = byPose[pose]!;
      final analysis = await _analyzeStill(
        sample.imageBytes,
        mirrored: sample.mirrored,
        expectedPose: pose,
      );
      if (analysis.failure != null) {
        return EnrollmentResult.failure(analysis.failure!);
      }
      embeddings[pose] = analysis.embedding!;
    }

    final consistency = minimumPairwiseSimilarity(embeddings.values);
    if (consistency < config.enrollmentConsistencyThreshold) {
      return EnrollmentResult.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.inconsistentEnrollment,
          'The three enrollment samples are not consistent enough.',
        ),
      );
    }
    return EnrollmentResult.success(
      FaceTemplate(
        templateId: _newTemplateId(),
        modelId: modelId,
        modelHash: modelHash,
        pipelineVersion: pipelineVersion,
        dimensions: embeddingDimensions,
        samples: embeddings,
        centroid: normalizedCentroid(embeddings.values),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Verifies one probe image against one compatible template.
  Future<VerificationResult> verify({
    required Uint8List imageBytes,
    required FaceTemplate template,
    bool mirrored = false,
    double? threshold,
  }) {
    final effectiveThreshold = threshold ?? config.verificationThreshold;
    if (!effectiveThreshold.isFinite ||
        effectiveThreshold < 0 ||
        effectiveThreshold > 1) {
      throw ArgumentError.value(effectiveThreshold, 'threshold');
    }
    return _runStill(
      () => _verify(imageBytes, template, mirrored, effectiveThreshold),
    );
  }

  Future<VerificationResult> _verify(
    Uint8List bytes,
    FaceTemplate template,
    bool mirrored,
    double threshold,
  ) async {
    final compatibility = validateTemplate(template);
    if (compatibility != null) {
      return VerificationResult(
        isMatch: false,
        similarity: 0,
        threshold: threshold,
        failure: compatibility,
      );
    }
    final analysis = await _analyzeStill(
      bytes,
      mirrored: mirrored,
      verification: true,
    );
    if (analysis.failure != null) {
      return VerificationResult(
        isMatch: false,
        similarity: 0,
        threshold: threshold,
        failure: analysis.failure,
      );
    }
    final probe = analysis.embedding!;
    final similarity = compareEmbeddings(probe, template.centroid);
    final sampleScores = {
      for (final entry in template.samples.entries)
        entry.key: compareEmbeddings(probe, entry.value),
    };
    final matched = similarity >= threshold;
    return VerificationResult(
      isMatch: matched,
      similarity: similarity,
      threshold: threshold,
      sampleSimilarities: sampleScores,
      failure: matched
          ? null
          : const FaceMatchFailure(
              FaceMatchErrorCode.belowThreshold,
              'The captured face did not match the enrolled template.',
            ),
    );
  }

  /// Returns a typed failure when a template belongs to another pipeline.
  FaceMatchFailure? validateTemplate(FaceTemplate template) {
    if (template.schemaVersion != FaceTemplate.currentSchemaVersion ||
        template.modelId != modelId ||
        template.modelHash != modelHash ||
        template.pipelineVersion != pipelineVersion ||
        template.dimensions != embeddingDimensions) {
      return const FaceMatchFailure(
        FaceMatchErrorCode.incompatibleTemplate,
        'This template is incompatible. Re-enrollment is required.',
      );
    }
    return null;
  }

  double compareEmbeddings(List<double> a, List<double> b) =>
      cosineSimilarity(a, b);

  FaceQuality evaluateQuality(DetectedFace face, {bool verification = false}) {
    final issues = <FaceQualityIssue>[];
    if (face.score < config.minimumDetectionScore) {
      issues.add(FaceQualityIssue.betterLighting);
    }
    if (face.faceFraction < config.minimumFaceFraction) {
      issues.add(FaceQualityIssue.moveCloser);
    }
    if (face.pitch == null || face.roll == null) {
      issues.add(FaceQualityIssue.landmarksUnavailable);
    }
    if (face.pitch != null && face.pitch!.abs() > config.maximumPitch) {
      issues.add(FaceQualityIssue.keepLevel);
    }
    if (face.roll != null && face.roll!.abs() > config.maximumRoll) {
      issues.add(FaceQualityIssue.straightenHead);
    }
    if (verification &&
        (face.yaw == null || face.yaw!.abs() > config.maximumVerificationYaw)) {
      issues.add(FaceQualityIssue.lookStraight);
    }
    return FaceQuality(isAcceptable: issues.isEmpty, issues: issues);
  }

  Future<_StillAnalysis> _analyzeStill(
    Uint8List bytes, {
    required bool mirrored,
    FacePose? expectedPose,
    bool verification = false,
  }) async {
    try {
      final result = await _engine
          .analyzeStill(bytes, mirrored: mirrored, embedding: true)
          .timeout(config.stillProcessingTimeout);
      final detection = _publicDetection(result);
      if (detection.failure != null) {
        return _StillAnalysis.failure(detection.failure!);
      }
      final face = detection.faces.single;
      final quality = evaluateQuality(face, verification: verification);
      if (!quality.isAcceptable) {
        return _StillAnalysis.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.lowQuality,
            faceQualityIssueMessage(quality.issues.first),
          ),
        );
      }
      if (expectedPose != null && !_poseMatches(expectedPose, face.yaw)) {
        return _StillAnalysis.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.wrongPose,
            _poseInstruction(expectedPose),
          ),
        );
      }
      final raw = result['embedding'];
      if (raw is! List || raw.length != embeddingDimensions) {
        return const _StillAnalysis.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.processingFailure,
            'The recognition model returned an invalid feature.',
          ),
        );
      }
      return _StillAnalysis.success(
        raw.map((value) => (value as num).toDouble()).toList(growable: false),
      );
    } on TimeoutException {
      return const _StillAnalysis.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.operationTimeout,
          'Still-image face processing timed out.',
        ),
      );
    } on FormatException {
      return const _StillAnalysis.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.invalidImage,
          'The image is malformed or exceeds the configured limits.',
        ),
      );
    } catch (_) {
      return const _StillAnalysis.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Face processing could not be completed.',
        ),
      );
    }
  }

  FaceDetectionResult _publicDetection(Map<String, Object?> result) {
    final rawFaces = result['faces'];
    if (rawFaces is! List) {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'The face detector returned malformed data.',
        ),
      );
    }
    final faces = rawFaces
        .map((raw) => _toPublicFace(Map<String, Object?>.from(raw as Map)))
        .toList(growable: false);
    if (faces.isEmpty) {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.noFace,
          'No face was detected.',
        ),
      );
    }
    if (faces.length > 1) {
      return FaceDetectionResult(
        faces: faces,
        failure: const FaceMatchFailure(
          FaceMatchErrorCode.multipleFaces,
          'Only one face may be visible.',
        ),
      );
    }
    return FaceDetectionResult(
      faces: faces,
      quality: evaluateQuality(faces.single),
    );
  }

  DetectedFace _toPublicFace(Map<String, Object?> raw) {
    final box = (raw['box']! as List).cast<num>();
    return DetectedFace(
      box: FaceBox(
        left: box[0].toDouble(),
        top: box[1].toDouble(),
        right: box[2].toDouble(),
        bottom: box[3].toDouble(),
      ),
      score: (raw['score']! as num).toDouble(),
      faceFraction: (raw['faceFraction']! as num).toDouble(),
      pitch: (raw['pitch'] as num?)?.toDouble(),
      yaw: (raw['yaw'] as num?)?.toDouble(),
      roll: (raw['roll'] as num?)?.toDouble(),
      leftEyeOpenProbability: (raw['leftEyeOpenProbability'] as num?)
          ?.toDouble(),
      rightEyeOpenProbability: (raw['rightEyeOpenProbability'] as num?)
          ?.toDouble(),
    );
  }

  bool _poseMatches(FacePose pose, double? yaw) {
    if (yaw == null) return false;
    return switch (pose) {
      FacePose.front => yaw >= -12 && yaw <= 12,
      FacePose.slightLeft => yaw >= 10 && yaw <= 42,
      FacePose.slightRight => yaw >= -42 && yaw <= -10,
    };
  }

  String _poseInstruction(FacePose pose) => switch (pose) {
    FacePose.front => 'Look straight at the camera.',
    FacePose.slightLeft => 'Turn your head slightly left.',
    FacePose.slightRight => 'Turn your head slightly right.',
  };

  Future<T> _runStill<T>(Future<T> Function() operation) {
    if (_disposed) throw StateError('FaceMatchKit has been disposed.');
    return _track(operation);
  }

  Future<T> _runLive<T>(Future<T> Function() operation) {
    if (_disposed) throw StateError('FaceMatchKit has been disposed.');
    return _track(operation);
  }

  Future<T> _track<T>(Future<T> Function() operation) async {
    _activeOperations++;
    try {
      return await operation();
    } finally {
      _activeOperations--;
      if (_activeOperations == 0 && _idleCompleter != null) {
        _idleCompleter!.complete();
        _idleCompleter = null;
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_activeOperations > 0) {
      _idleCompleter ??= Completer<void>();
      await _idleCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    }
    await _engine.dispose();
    await _deleteTemporaryFile(_temporarySfacePath);
  }
}

class _StillAnalysis {
  final List<double>? embedding;
  final FaceMatchFailure? failure;

  const _StillAnalysis.success(this.embedding) : failure = null;
  const _StillAnalysis.failure(this.failure) : embedding = null;
}

String _newTemplateId() {
  final random = math.Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _deleteTemporaryFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Temporary model cleanup is best effort; no biometric image is stored.
  }
}

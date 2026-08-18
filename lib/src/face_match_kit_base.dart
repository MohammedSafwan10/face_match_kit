import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as fd;
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart' as litert;

import 'face_match_config.dart';
import 'face_match_models.dart';
import 'image_normalizer.dart';

/// Rotation applied to a live camera buffer before detection.
enum FaceCameraRotation { none, clockwise90, clockwise180, clockwise270 }

/// On-device face detector, enrollment engine, and 1:1 verifier.
class FaceMatchKit {
  static const String modelId = 'mobilefacenet-192';
  static const String modelHash =
      'be4bc7cfc53f7bc336d0f28b1ab92535f618c913a422b683210750f6b5354854';
  static const String pipelineAssetSetHash =
      '78e54734adb404c24df8899c7ba8bcddffc79a44c25d782125da37d615d7fd62';
  static const String pipelineVersion =
      'canonical-png-eye-align-v2+detector-${fd.FaceDetector.modelVersion}'
      '+assets-$pipelineAssetSetHash';
  static const int embeddingDimensions = 192;

  static const Map<String, String> _modelAssetHashes = {
    'face_detection_front.tflite':
        '3bc182eb9f33925d9e58b5c8d59308a760f4adea8f282370e428c51212c26633',
    'face_landmark.tflite':
        '2efcb4f4de43c7614b80a3cc3e8a37354b3b3b40f75cce20f6f38f0f25d65493',
    'iris_landmark.tflite':
        'd1744d2a09c25f501d39eba4faff47e53ecca8852c5ce19bce8eeac39357521f',
    'face_blendshapes.tflite':
        '4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082',
    'mobilefacenet.tflite': modelHash,
  };

  final FaceMatchConfig config;
  final fd.FaceDetector _detector;
  bool _disposed = false;
  int _activeOperations = 0;
  Completer<void>? _idleCompleter;
  Future<void> _operationTail = Future<void>.value();

  FaceMatchKit._(this.config, this._detector);

  static Future<FaceMatchKit> create({
    FaceMatchConfig config = const FaceMatchConfig(),
  }) async {
    config.validate();
    for (final entry in _modelAssetHashes.entries) {
      final data = await rootBundle.load(
        'packages/face_detection_tflite/assets/models/${entry.key}',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != entry.value) {
        throw StateError(
          'Face pipeline integrity check failed for ${entry.key}. Expected '
          '${entry.value} but loaded $actualHash. Upgrade face_match_kit or '
          'restore a compatible face_detection_tflite dependency.',
        );
      }
    }

    final detector = await fd.FaceDetector.create(
      model: fd.FaceDetectionModel.frontCamera,
      // Keep raw detections visible to the guidance UI. Quality thresholds
      // are applied by evaluateQuality(), where the host can explain how to
      // improve instead of turning a small/dim face into an ambiguous
      // "no face" result before landmarks are returned.
      minScore: 0,
      minFaceSize: 0,
    );
    return FaceMatchKit._(config, detector);
  }

  /// Detects faces in encoded JPEG/PNG bytes after canonical normalization.
  Future<FaceDetectionResult> detect(
    Uint8List imageBytes, {
    bool mirrored = false,
  }) => _runOperation(() => _detect(imageBytes, mirrored: mirrored));

  Future<FaceDetectionResult> _detect(
    Uint8List imageBytes, {
    required bool mirrored,
  }) async {
    try {
      final canonical = await canonicalizeImage(imageBytes, mirrored: mirrored);
      final faces = await _detector.detectFacesFromBytes(
        canonical,
        mode: fd.FaceDetectionMode.full,
      );
      return _publicDetection(faces);
    } on FormatException catch (error) {
      return FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.invalidImage,
          error.message,
        ),
      );
    } catch (_) {
      return FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Face detection could not be completed.',
        ),
      );
    }
  }

  /// Detects live camera pixels for guidance and liveness only.
  ///
  /// Enrollment and verification embeddings always use encoded still images.
  Future<FaceDetectionResult> detectCameraImage(
    Object cameraImage, {
    FaceCameraRotation rotation = FaceCameraRotation.none,
    bool isBgra = false,
  }) => _runOperation(
    () => _detectCameraImage(cameraImage, rotation: rotation, isBgra: isBgra),
  );

  Future<FaceDetectionResult> _detectCameraImage(
    Object cameraImage, {
    required FaceCameraRotation rotation,
    required bool isBgra,
  }) async {
    try {
      final faces = await _detector.detectFacesFromCameraImage(
        cameraImage,
        mode: fd.FaceDetectionMode.full,
        rotation: _cameraRotation(rotation),
        isBgra: isBgra,
        maxDim: 640,
      );
      return _publicDetection(faces);
    } catch (_) {
      return FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Live face detection could not be completed.',
        ),
      );
    }
  }

  Future<EnrollmentResult> enroll({required List<FaceSample> samples}) =>
      _runOperation(() => _enroll(samples: samples));

  Future<EnrollmentResult> _enroll({required List<FaceSample> samples}) async {
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
      final analysis = await _analyzeStill(
        byPose[pose]!.imageBytes,
        mirrored: byPose[pose]!.mirrored,
        expectedPose: pose,
      );
      if (analysis.failure != null) {
        return EnrollmentResult.failure(analysis.failure!);
      }
      try {
        final embedding = await _detector.getFaceEmbedding(
          analysis.face!,
          analysis.canonicalBytes!,
        );
        if (embedding.length != embeddingDimensions) {
          return EnrollmentResult.failure(
            FaceMatchFailure(
              FaceMatchErrorCode.processingFailure,
              'Model returned ${embedding.length} dimensions; '
              'expected $embeddingDimensions.',
            ),
          );
        }
        embeddings[pose] = embedding.toList(growable: false);
      } catch (_) {
        return EnrollmentResult.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.processingFailure,
            'Could not create the ${pose.name} embedding.',
          ),
        );
      }
    }

    final enrollmentSimilarity = minimumPairwiseSimilarity(embeddings.values);
    if (enrollmentSimilarity < config.enrollmentConsistencyThreshold) {
      return EnrollmentResult.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.inconsistentEnrollment,
          'Enrollment samples do not appear to show the same person '
          '(${enrollmentSimilarity.toStringAsFixed(3)} < '
          '${config.enrollmentConsistencyThreshold.toStringAsFixed(3)}). '
          'Please restart enrollment.',
        ),
      );
    }

    return EnrollmentResult.success(
      FaceTemplate(
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
      throw ArgumentError.value(
        effectiveThreshold,
        'threshold',
        'Must be finite and between 0 and 1.',
      );
    }
    return _runOperation(
      () => _verify(
        imageBytes: imageBytes,
        template: template,
        mirrored: mirrored,
        threshold: effectiveThreshold,
      ),
    );
  }

  Future<VerificationResult> _verify({
    required Uint8List imageBytes,
    required FaceTemplate template,
    required bool mirrored,
    required double threshold,
  }) async {
    final compatibilityFailure = _validateCompatibility(template);
    if (compatibilityFailure != null) {
      return VerificationResult(
        isMatch: false,
        similarity: 0,
        threshold: threshold,
        failure: compatibilityFailure,
      );
    }

    final analysis = await _analyzeStill(
      imageBytes,
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

    try {
      final probe = await _detector.getFaceEmbedding(
        analysis.face!,
        analysis.canonicalBytes!,
      );
      final similarity = compareEmbeddings(probe, template.centroid);
      final sampleScores = {
        for (final entry in template.samples.entries)
          entry.key: compareEmbeddings(probe, entry.value),
      };
      final isMatch = similarity >= threshold;
      return VerificationResult(
        isMatch: isMatch,
        similarity: similarity,
        threshold: threshold,
        sampleSimilarities: sampleScores,
        failure: isMatch
            ? null
            : const FaceMatchFailure(
                FaceMatchErrorCode.belowThreshold,
                'The captured face did not match the enrolled template.',
              ),
      );
    } catch (_) {
      return VerificationResult(
        isMatch: false,
        similarity: 0,
        threshold: threshold,
        failure: FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Face verification could not be completed.',
        ),
      );
    }
  }

  double compareEmbeddings(List<double> a, List<double> b) =>
      cosineSimilarity(a, b);

  FaceQuality evaluateQuality(DetectedFace face, {bool verification = false}) {
    final issues = <String>[];
    if (face.score < config.minimumDetectionScore) {
      issues.add('Move into better lighting.');
    }
    if (face.faceFraction < config.minimumFaceFraction) {
      issues.add('Move closer to the camera.');
    }
    if (face.pitch == null || face.roll == null) {
      issues.add('Hold still while facial landmarks are measured.');
    }
    if (face.pitch != null && face.pitch!.abs() > config.maximumPitch) {
      issues.add('Keep your face level.');
    }
    if (face.roll != null && face.roll!.abs() > config.maximumRoll) {
      issues.add('Straighten your head.');
    }
    if (verification && face.yaw == null) {
      issues.add('Look straight at the camera.');
    } else if (verification &&
        face.yaw!.abs() > config.maximumVerificationYaw) {
      issues.add('Look straight at the camera.');
    }
    return FaceQuality(isAcceptable: issues.isEmpty, issues: issues);
  }

  FaceMatchFailure? _validateCompatibility(FaceTemplate template) {
    if (template.schemaVersion != FaceTemplate.currentSchemaVersion ||
        template.modelId != modelId ||
        template.modelHash != modelHash ||
        template.pipelineVersion != pipelineVersion ||
        template.dimensions != embeddingDimensions) {
      return const FaceMatchFailure(
        FaceMatchErrorCode.incompatibleTemplate,
        'This template was created by an incompatible model or pipeline. '
        'Re-enrollment is required.',
      );
    }
    return null;
  }

  Future<_StillAnalysis> _analyzeStill(
    Uint8List bytes, {
    required bool mirrored,
    FacePose? expectedPose,
    bool verification = false,
  }) async {
    try {
      final canonical = await canonicalizeImage(bytes, mirrored: mirrored);
      final faces = await _detector.detectFacesFromBytes(
        canonical,
        mode: fd.FaceDetectionMode.full,
      );
      if (faces.isEmpty) {
        return const _StillAnalysis.failure(
          FaceMatchFailure(FaceMatchErrorCode.noFace, 'No face was detected.'),
        );
      }
      if (faces.length != 1) {
        return const _StillAnalysis.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.multipleFaces,
            'Only one face may be visible.',
          ),
        );
      }

      final publicFace = _toPublicFace(faces.single);
      final quality = evaluateQuality(publicFace, verification: verification);
      if (!quality.isAcceptable) {
        return _StillAnalysis.failure(
          FaceMatchFailure(FaceMatchErrorCode.lowQuality, quality.issues.first),
        );
      }
      if (expectedPose != null && !_poseMatches(expectedPose, publicFace.yaw)) {
        return _StillAnalysis.failure(
          FaceMatchFailure(
            FaceMatchErrorCode.wrongPose,
            _poseInstruction(expectedPose),
          ),
        );
      }
      return _StillAnalysis.success(canonical, faces.single);
    } on FormatException catch (error) {
      return _StillAnalysis.failure(
        FaceMatchFailure(FaceMatchErrorCode.invalidImage, error.message),
      );
    } catch (_) {
      return _StillAnalysis.failure(
        FaceMatchFailure(
          FaceMatchErrorCode.processingFailure,
          'Face processing could not be completed.',
        ),
      );
    }
  }

  FaceDetectionResult _publicDetection(List<fd.Face> faces) {
    final publicFaces = faces.map(_toPublicFace).toList(growable: false);
    if (publicFaces.isEmpty) {
      return const FaceDetectionResult(
        failure: FaceMatchFailure(
          FaceMatchErrorCode.noFace,
          'No face was detected.',
        ),
      );
    }
    if (publicFaces.length > 1) {
      return FaceDetectionResult(
        faces: publicFaces,
        failure: const FaceMatchFailure(
          FaceMatchErrorCode.multipleFaces,
          'Only one face may be visible.',
        ),
      );
    }
    final quality = evaluateQuality(publicFaces.single);
    return FaceDetectionResult(faces: publicFaces, quality: quality);
  }

  DetectedFace _toPublicFace(fd.Face face) {
    final box = face.boundingBox;
    return DetectedFace(
      box: FaceBox(
        left: box.left,
        top: box.top,
        right: box.right,
        bottom: box.bottom,
      ),
      score: face.score,
      faceFraction: face.widthFraction,
      pitch: face.headEulerAngleX,
      yaw: face.headEulerAngleY,
      roll: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
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

  litert.CameraFrameRotation? _cameraRotation(FaceCameraRotation rotation) =>
      switch (rotation) {
        FaceCameraRotation.none => null,
        FaceCameraRotation.clockwise90 => litert.CameraFrameRotation.cw90,
        FaceCameraRotation.clockwise180 => litert.CameraFrameRotation.cw180,
        FaceCameraRotation.clockwise270 => litert.CameraFrameRotation.cw270,
      };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_activeOperations > 0) {
      _idleCompleter ??= Completer<void>();
      await _idleCompleter!.future;
    }
    await _detector.dispose();
  }

  Future<T> _runOperation<T>(Future<T> Function() operation) async {
    if (_disposed) {
      throw StateError('FaceMatchKit has been disposed.');
    }
    _activeOperations++;
    final previous = _operationTail;
    final result = previous.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, _) {});
    try {
      return await result;
    } finally {
      _activeOperations--;
      if (_activeOperations == 0 && _idleCompleter != null) {
        _idleCompleter!.complete();
        _idleCompleter = null;
      }
    }
  }
}

class _StillAnalysis {
  final Uint8List? canonicalBytes;
  final fd.Face? face;
  final FaceMatchFailure? failure;

  const _StillAnalysis.success(this.canonicalBytes, this.face) : failure = null;
  const _StillAnalysis.failure(this.failure)
    : canonicalBytes = null,
      face = null;
}

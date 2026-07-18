/// Configuration for detection, enrollment, and verification.
class FaceMatchConfig {
  /// Provisional default from the bundled embedding model.
  ///
  /// Production applications should calibrate this against their own capture
  /// conditions and false-accept/false-reject requirements.
  final double verificationThreshold;

  /// Minimum pairwise similarity required among all enrollment poses.
  ///
  /// This is a safety gate against accidentally combining different people.
  /// It is provisional and must be calibrated with the verification policy.
  final double enrollmentConsistencyThreshold;

  /// Smallest accepted face width as a fraction of image width.
  final double minimumFaceFraction;

  /// Minimum detector confidence.
  final double minimumDetectionScore;

  /// Maximum pitch accepted for enrollment and verification.
  final double maximumPitch;

  /// Maximum roll accepted for enrollment and verification.
  final double maximumRoll;

  /// Maximum absolute yaw accepted for a frontal verification capture.
  final double maximumVerificationYaw;

  /// Whether camera widgets run the basic randomized liveness challenge.
  final bool livenessEnabled;

  /// Number of distinct liveness actions in a challenge.
  final int livenessActionCount;

  /// Maximum time allowed to complete one basic liveness action.
  final Duration livenessActionTimeout;

  /// Live frames that may miss a face before the challenge is restarted.
  final int livenessFaceLossTolerance;

  /// Delay after each processed live frame.
  final Duration liveDetectionInterval;

  const FaceMatchConfig({
    this.verificationThreshold = 0.60,
    this.enrollmentConsistencyThreshold = 0.45,
    this.minimumFaceFraction = 0.18,
    this.minimumDetectionScore = 0.65,
    this.maximumPitch = 30,
    this.maximumRoll = 25,
    this.maximumVerificationYaw = 18,
    this.livenessEnabled = true,
    this.livenessActionCount = 2,
    this.livenessActionTimeout = const Duration(seconds: 10),
    this.livenessFaceLossTolerance = 3,
    this.liveDetectionInterval = const Duration(milliseconds: 120),
  });

  /// Validates configuration in debug and release builds.
  void validate() {
    _requireUnitInterval(verificationThreshold, 'verificationThreshold');
    _requireUnitInterval(
      enrollmentConsistencyThreshold,
      'enrollmentConsistencyThreshold',
    );
    if (!minimumFaceFraction.isFinite ||
        minimumFaceFraction <= 0 ||
        minimumFaceFraction > 1) {
      throw ArgumentError.value(
        minimumFaceFraction,
        'minimumFaceFraction',
        'Must be finite and greater than 0 through 1.',
      );
    }
    _requireUnitInterval(minimumDetectionScore, 'minimumDetectionScore');
    _requireAngle(maximumPitch, 'maximumPitch', 90);
    _requireAngle(maximumRoll, 'maximumRoll', 180);
    _requireAngle(maximumVerificationYaw, 'maximumVerificationYaw', 90);
    if (livenessActionCount < 1 || livenessActionCount > 3) {
      throw ArgumentError.value(
        livenessActionCount,
        'livenessActionCount',
        'Must be between 1 and 3.',
      );
    }
    if (livenessActionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        livenessActionTimeout,
        'livenessActionTimeout',
        'Must be positive.',
      );
    }
    if (livenessFaceLossTolerance < 1) {
      throw ArgumentError.value(
        livenessFaceLossTolerance,
        'livenessFaceLossTolerance',
        'Must be at least 1.',
      );
    }
    if (liveDetectionInterval.isNegative) {
      throw ArgumentError.value(
        liveDetectionInterval,
        'liveDetectionInterval',
        'Must not be negative.',
      );
    }
  }

  static void _requireUnitInterval(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and between 0 and 1.',
      );
    }
  }

  static void _requireAngle(double value, String name, double maximum) {
    if (!value.isFinite || value < 0 || value > maximum) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and between 0 and $maximum degrees.',
      );
    }
  }
}

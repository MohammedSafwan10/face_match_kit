import '../liveness.dart';
import 'face_match_theme.dart';

/// Resolves liveness copy without assuming an incomplete UI timer means the
/// session still has a current action.
String livenessGuidanceOrFallback({
  required FaceMatchTexts texts,
  required LivenessSession? session,
  required bool challengeComplete,
  required String fallback,
}) {
  final action = session?.currentAction;
  if (challengeComplete || action == null) return fallback;
  return texts.livenessStep(action, session!.currentPhase);
}

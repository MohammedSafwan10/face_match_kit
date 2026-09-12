import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_match_kit/face_match_kit.dart';

void main() {
  final epoch = DateTime.utc(2026);
  DetectedFace face(double yaw, {double width = .3}) => DetectedFace(
    box: FaceBox(left: .3, top: .2, right: .3 + width, bottom: .6),
    score: .99,
    faceFraction: width,
    yaw: yaw,
  );
  double yaw(FacePose pose) => switch (pose) {
    FacePose.front => 0,
    FacePose.slightLeft => 20,
    FacePose.slightRight => -20,
  };
  void stable(CaptureFlow f, int start) {
    final target = yaw(f.pose);
    for (final ms in [0, 150, 300]) {
      f.update(
        face(target),
        multiple: false,
        quality: true,
        now: epoch.add(Duration(milliseconds: start + ms)),
      );
    }
  }

  test('normalized small face remains continuous', () {
    for (final width in [.2, .3, .4]) {
      expect(
        CaptureFlow.continuous(
          face(0, width: width).box,
          face(0, width: width).box,
        ),
        isTrue,
      );
    }
    expect(
      CaptureFlow.continuous(
        null,
        const FaceBox(left: 0, top: 0, right: 0, bottom: 1),
      ),
      isFalse,
    );
  });
  test('pose ranges do not overlap', () {
    // Live windows mirror FaceMatchKit._poseMatches (front ±12, sides 10-42).
    expect(CaptureFlow.matches(FacePose.front, 12), isTrue);
    expect(CaptureFlow.matches(FacePose.front, 13), isFalse);
    expect(CaptureFlow.matches(FacePose.slightLeft, 9), isFalse);
    expect(CaptureFlow.matches(FacePose.slightLeft, 10), isTrue);
    expect(CaptureFlow.matches(FacePose.slightRight, -10), isTrue);
    expect(CaptureFlow.matches(FacePose.slightRight, -9), isFalse);
    expect(CaptureFlow.matches(FacePose.slightRight, -42), isTrue);
    expect(CaptureFlow.matches(FacePose.slightRight, -43), isFalse);
  });
  test('enrollment captures all three semantic poses with stable frames', () {
    final f = CaptureFlow(
      CaptureFlowPolicy.guidedEnrollment,
      random: Random(1),
    );
    expect(f.poses.toSet(), FacePose.values.toSet());
    for (var i = 0; i < 3; i++) {
      stable(f, i * 1000);
      expect(f.ready, isTrue);
      f.captured();
      expect(f.ready, isFalse);
    }
    expect(f.step, 3);
  });
  test('verification requires center turn return and no blink', () {
    final f = CaptureFlow(CaptureFlowPolicy.singleTurnVerification);
    stable(f, 0);
    expect(f.step, 1);
    expect(f.ready, isFalse);
    stable(f, 450);
    expect(f.step, 2);
    expect(f.ready, isFalse);
    stable(f, 900);
    expect(f.ready, isTrue);
  });
  test('simple verification needs one straight look only', () {
    final f = CaptureFlow(CaptureFlowPolicy.simpleVerification);
    expect(f.poses, const [FacePose.front]);
    stable(f, 0);
    expect(f.ready, isTrue);
    expect(f.step, 0);
  });
  test('three fast frames alone are not sufficient', () {
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    for (var i = 0; i < 4; i++) {
      f.update(
        face(0),
        multiple: false,
        quality: true,
        now: epoch.add(Duration(milliseconds: i * 10)),
      );
    }
    expect(f.ready, isFalse);
  });
  test('multiple faces reset immediately', () {
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    stable(f, 0);
    f.captured();
    expect(
      f.update(
        null,
        multiple: true,
        quality: false,
        now: epoch.add(const Duration(milliseconds: 350)),
      ),
      isTrue,
    );
    expect(f.step, 0);
  });
  test('short loss pauses and long loss resets', () {
    final f = CaptureFlow(CaptureFlowPolicy.singleTurnVerification);
    stable(f, 0);
    // Gap tolerance is 1500ms to cover on-device inference latency; a 600ms
    // stall only pauses, while a stall past the tolerance resets.
    expect(
      f.update(
        null,
        multiple: false,
        quality: false,
        now: epoch.add(const Duration(milliseconds: 600)),
      ),
      isFalse,
    );
    expect(
      f.update(
        null,
        multiple: false,
        quality: false,
        now: epoch.add(const Duration(milliseconds: 1900)),
      ),
      isTrue,
    );
    expect(f.step, 0);
  });
  test('quality recovery schedules readiness', () {
    final f = CaptureFlow(CaptureFlowPolicy.singleTurnVerification);
    stable(f, 0);
    stable(f, 450);
    f.update(
      face(0),
      multiple: false,
      quality: false,
      now: epoch.add(const Duration(milliseconds: 900)),
    );
    expect(f.ready, isFalse);
    stable(f, 1050);
    expect(f.ready, isTrue);
  });
  test('enrollment deadline survives intentional stream pauses', () {
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    stable(f, 0);
    f.captured();
    expect(
      f.update(
        face(20),
        multiple: false,
        quality: true,
        now: epoch.add(const Duration(seconds: 31)),
      ),
      isTrue,
    );
    expect(f.step, 0);
  });
  test('both randomized side orders are reachable', () {
    final orders = {
      for (var seed = 0; seed < 30; seed++)
        CaptureFlow(
          CaptureFlowPolicy.guidedEnrollment,
          random: Random(seed),
        ).poses[1],
    };
    expect(orders.length, 2);
  });
  test('completed verification expires even with continuous frames', () {
    final f = CaptureFlow(CaptureFlowPolicy.singleTurnVerification);
    stable(f, 0);
    stable(f, 450);
    stable(f, 900);
    for (var ms = 1350; ms <= 6150; ms += 150) {
      expect(
        f.update(
          face(0),
          multiple: false,
          quality: true,
          now: epoch.add(Duration(milliseconds: ms)),
        ),
        isFalse,
      );
    }
    expect(
      f.update(
        face(0),
        multiple: false,
        quality: true,
        now: epoch.add(const Duration(milliseconds: 6300)),
      ),
      isTrue,
    );
    expect(f.ready, isFalse);
  });
  test('reset clears capture readiness and prior stage', () {
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    stable(f, 0);
    f.captured();
    f.reset();
    expect(f.step, 0);
    expect(f.ready, isFalse);
    expect(() => f.captured(), throwsStateError);
  });
  test('face jump invalidates progress', () {
    final f = CaptureFlow(CaptureFlowPolicy.singleTurnVerification);
    stable(f, 0);
    const other = DetectedFace(
      box: FaceBox(left: .75, top: .2, right: .95, bottom: .6),
      score: .99,
      faceFraction: .2,
      yaw: 0,
    );
    expect(
      f.update(
        other,
        multiple: false,
        quality: true,
        now: epoch.add(const Duration(milliseconds: 450)),
      ),
      isTrue,
    );
    expect(f.step, 0);
  });
  test('slow inference cadence still reaches readiness', () {
    // Regression for HR enrollment stuck on step 1: on-device inference +
    // Dart YUV conversion routinely spaces processed frames 500-800ms apart.
    // That must not count as face loss.
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    for (final ms in [0, 600, 1200]) {
      expect(
        f.update(
          face(0),
          multiple: false,
          quality: true,
          now: epoch.add(Duration(milliseconds: ms)),
        ),
        isFalse,
      );
    }
    expect(f.ready, isTrue);
  });
  test('borderline straight yaw is accepted like the still gate', () {
    // Still enrollment accepts front ±12; live must too, else a user with a
    // natural 10° yaw stares straight forever with no progress.
    final f = CaptureFlow(CaptureFlowPolicy.guidedEnrollment);
    for (final ms in [0, 150, 300]) {
      f.update(
        face(10),
        multiple: false,
        quality: true,
        now: epoch.add(Duration(milliseconds: ms)),
      );
    }
    expect(f.ready, isTrue);
  });
  test('legacy and single-turn verification share one behavior', () {
    // Both map to [front, side, front]; pin the equivalence so a future
    // divergence is deliberate, not accidental.
    final legacy = CaptureFlow(CaptureFlowPolicy.legacy, random: Random(7));
    final turn = CaptureFlow(
      CaptureFlowPolicy.singleTurnVerification,
      random: Random(7),
    );
    expect(legacy.poses, turn.poses);
    expect(legacy.poses.first, FacePose.front);
    expect(legacy.poses.last, FacePose.front);
  });
  test('captured() is enrollment-only', () {
    final f = CaptureFlow(CaptureFlowPolicy.simpleVerification);
    stable(f, 0);
    expect(f.ready, isTrue);
    expect(() => f.captured(), throwsStateError);
  });
  test('reset clears simple-verification readiness', () {
    final f = CaptureFlow(CaptureFlowPolicy.simpleVerification);
    stable(f, 0);
    expect(f.ready, isTrue);
    f.reset();
    expect(f.ready, isFalse);
    expect(f.step, 0);
  });
}

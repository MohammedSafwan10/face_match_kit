import 'package:face_match_kit/src/frame_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(milliseconds: 120);
  test('fast inference waits only the unused interval', () {
    expect(
      remainingFrameDelay(interval, const Duration(milliseconds: 80)),
      const Duration(milliseconds: 40),
    );
  });
  test('inference at the interval needs no extra pause', () {
    expect(remainingFrameDelay(interval, interval), Duration.zero);
  });
  test('slow inference never adds an extra pause or negative delay', () {
    expect(
      remainingFrameDelay(interval, const Duration(milliseconds: 450)),
      Duration.zero,
    );
  });
}

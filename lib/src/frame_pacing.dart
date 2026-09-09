/// Remaining idle time for a minimum start-to-start detection interval.
/// Slow inference already consumes the interval and must not add more delay.
Duration remainingFrameDelay(Duration interval, Duration elapsed) {
  final remaining = interval - elapsed;
  return remaining > Duration.zero ? remaining : Duration.zero;
}

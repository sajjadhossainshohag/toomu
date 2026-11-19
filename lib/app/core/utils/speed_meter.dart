/// Download speed over the last [window], fed a byte count on every UI tick.
/// Ticks can come faster than the window (progress moves 4× a second) while
/// the speed stays as steady as a once-a-second reading.
class SpeedMeter {
  SpeedMeter(int startBytes, Duration at, {this.window = const Duration(seconds: 1)}) {
    _samples.add((at, startBytes));
  }

  final Duration window;
  final List<(Duration, int)> _samples = [];

  /// Bytes per second from the oldest sample still inside [window] to now.
  int add(int bytes, Duration at) {
    _samples.add((at, bytes));
    // Keep one sample at or just past the window's start.
    while (_samples.length > 2 && at - _samples[1].$1 >= window) {
      _samples.removeAt(0);
    }
    final (t0, b0) = _samples.first;
    final ms = (at - t0).inMilliseconds;
    if (ms <= 0) return 0;
    return ((bytes - b0) * 1000 / ms).round().clamp(0, 1 << 40);
  }
}

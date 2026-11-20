import 'dart:async';

/// Seeking while a finger drags (the seek bar or a sideways swipe): the picture follows, like MX.
///
/// Every move would be one seek per finger event (~60 a second) and the decoder would never catch up, so
/// moves are sent at most once per [interval] as fast keyframe seeks; the last position is always sent.
/// Letting go cancels what is pending and seeks exactly there.
class LiveSeek {
  LiveSeek({required this.fast, required this.exact, this.interval = const Duration(milliseconds: 150)});

  final void Function(Duration to) fast;
  final void Function(Duration to) exact;
  final Duration interval;

  Timer? _cooldown;
  Duration? _pending;

  void drag(Duration to) {
    if (_cooldown?.isActive ?? false) {
      _pending = to;
      return;
    }
    fast(to);
    _wait();
  }

  void _wait() {
    _cooldown = Timer(interval, () {
      final next = _pending;
      _pending = null;
      if (next == null) return;
      fast(next);
      _wait();
    });
  }

  void end(Duration to) {
    cancel();
    exact(to);
  }

  void cancel() {
    _cooldown?.cancel();
    _pending = null;
  }
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The player's touch surface: taps, double taps and swipes.
///
/// Flutter's own double-tap holds every single tap back ~300 ms to see if a second one follows, so the
/// controls came up late (MX and YouTube show them at once). Here every tap acts at once; a second tap
/// soon after and close by is a double tap (skip), and more quick taps keep skipping. The player undoes
/// the first tap's show/hide when it turns out to be a double tap.
class PlayerTapArea extends StatefulWidget {
  const PlayerTapArea({
    required this.onTap,
    required this.onDoubleTap,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    super.key,
  });

  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset> onDoubleTap;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  @override
  State<PlayerTapArea> createState() => _PlayerTapAreaState();
}

class _PlayerTapAreaState extends State<PlayerTapArea> {
  Timer? _window;
  Offset? _last;

  void _onTapUp(TapUpDetails d) {
    final at = d.localPosition;
    final last = _last;
    final double = _window?.isActive == true && last != null && (at - last).distance <= kDoubleTapSlop;
    _last = at;
    _window?.cancel();
    _window = Timer(kDoubleTapTimeout, () => _last = null);
    double ? widget.onDoubleTap(at) : widget.onTap(at);
  }

  @override
  void dispose() {
    _window?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: _onTapUp,
    onScaleStart: widget.onScaleStart,
    onScaleUpdate: widget.onScaleUpdate,
    onScaleEnd: widget.onScaleEnd,
  );
}

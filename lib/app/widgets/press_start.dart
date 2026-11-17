import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class PressStart extends StatefulWidget {
  const PressStart({required this.onStart, required this.child, super.key});

  final VoidCallback onStart;
  final Widget child;

  @override
  State<PressStart> createState() => _PressStartState();
}

class _PressStartState extends State<PressStart> {
  // A scroll gives itself away by moving within this time; a tap doesn't.
  static const _delay = Duration(milliseconds: 50);

  Timer? _timer;
  Offset _down = Offset.zero;

  void _fire() {
    _timer?.cancel();
    _timer = null;
    widget.onStart();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) {
          _down = e.position;
          _timer?.cancel();
          _timer = Timer(_delay, _fire);
        },
        onPointerMove: (e) {
          if ((e.position - _down).distance > kTouchSlop) _cancel();
        },
        onPointerUp: (_) {
          if (_timer != null) _fire();
        },
        onPointerCancel: (_) => _cancel(),
        child: widget.child,
      );
}

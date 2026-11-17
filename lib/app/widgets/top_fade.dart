import 'package:flutter/material.dart';

import '../core/theme/design_metrics.dart';

/// Fades scrolling content out under a header instead of a hard edge.
class TopFade extends StatelessWidget {
  const TopFade({required this.child, this.extent = 24, super.key});

  final Widget child;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).scaffoldBackgroundColor;
    // A gradient painted over the list, not a ShaderMask: a mask renders the
    // whole scrolling list offscreen again on every frame.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: extent * context.scale,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[background, background.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

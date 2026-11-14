import 'package:flutter/material.dart';

import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Fades scrolling content out under a header instead of a hard edge.
class TopFade extends StatelessWidget {
  const TopFade({required this.child, this.extent = 24, super.key});

  final Widget child;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final double fade = extent * context.scale;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) {
        final double stop =
            bounds.height <= 0 ? 0 : (fade / bounds.height).clamp(0, 1).toDouble();
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[ColorConstants.transparent, ColorConstants.black],
          stops: <double>[0, stop],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

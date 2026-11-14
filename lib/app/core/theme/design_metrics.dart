import 'package:flutter/material.dart';

/// Designs are drawn on a 375pt-wide frame; every size is multiplied by
/// [scaleOf] so layouts keep their proportions on any phone.
class DesignMetrics {
  const DesignMetrics._();

  static const double frameWidth = 375;

  /// Horizontal page gutter.
  static const double gutter = 16;

  /// Based on the *shortest* side, not the width: in landscape (or while
  /// rotating) the width jumps to ~850 and a width-based scale blew every
  /// widget up ~2.3× for those frames, overflowing the screen (the yellow /
  /// black stripes). Clamped so small phones stay readable and tablets
  /// don't get giant controls.
  static double scaleOf(BuildContext context) =>
      (MediaQuery.sizeOf(context).shortestSide / frameWidth).clamp(0.85, 1.3);
}

extension DesignContext on BuildContext {
  double get scale => DesignMetrics.scaleOf(this);

  /// Reads the active Theme (not the platform) so the manual theme mode wins.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

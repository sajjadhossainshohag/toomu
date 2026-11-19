import 'package:flutter/material.dart';

import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import '../core/utils/formatters.dart';
import 'gradient_progress_bar.dart';

/// The update download's bar with "42% · 12.3 MB of 30.0 MB" under it.
class UpdateProgress extends StatelessWidget {
  const UpdateProgress({required this.received, required this.total, super.key});

  final int received;

  /// 0 while the size isn't known yet.
  final int total;

  static String label(int received, int total) {
    if (total <= 0) return received > 0 ? Formatters.bytes(received) : 'Starting…';
    final percent = (received * 100 ~/ total).clamp(0, 100);
    return '$percent% · ${Formatters.bytes(received)} of ${Formatters.bytes(total)}';
  }

  @override
  Widget build(BuildContext context) {
    final scale = context.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GradientProgressBar(value: total > 0 ? received / total : 0),
        SizedBox(height: 10 * scale),
        Text(
          label(received, total),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

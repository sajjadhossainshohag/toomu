import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({
    required this.value,
    this.height = 6,
    this.color,
    super.key,
  });

  /// 0..1
  final double value;
  final double height;

  /// Solid color override (e.g. paused/failed state).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final double h = height * scale;
    return ClipRRect(
      borderRadius: BorderRadius.circular(h),
      child: SizedBox(
        height: h,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: ColorConstants.textOn(context.isDark)
                    .withValues(alpha: context.isDark ? 0.08 : 0.08),
              ),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  gradient: color == null ? BrandColors.of(context).progressGradient : null,
                  borderRadius: BorderRadius.circular(h),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

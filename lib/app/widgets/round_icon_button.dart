import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Circular icon button. [filled] = brand pill gradient (primary action),
/// [active] = tinted brand background (toggled state), otherwise subtle.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize,
    this.filled = false,
    this.active = false,
    this.tooltip,
    this.badge,
    this.gradient,
    super.key,
  });

  /// Fill for [filled] buttons instead of the brand gradient (e.g. a second
  /// primary action that should look different).
  final Gradient? gradient;

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double? iconSize;
  final bool filled;
  final bool active;
  final String? tooltip;

  /// Tiny label drawn under the icon (e.g. "1.5x", "A-B").
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = ColorConstants.textOn(dark);

    final Color fg = filled
        ? ColorConstants.white
        : active
            ? (dark ? brand.accent : brand.primary)
            : ink.withValues(alpha: 0.75);

    final Widget button = Material(
      color: ColorConstants.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled ? (gradient ?? brand.pillGradient) : null,
          color: filled
              ? null
              : active
                  ? brand.primary.withValues(alpha: dark ? 0.24 : 0.12)
                  : ColorConstants.transparent,
          boxShadow: filled
              ? <BoxShadow>[
                  BoxShadow(
                    color: (gradient?.colors.last ?? brand.primary).withValues(alpha: 0.35),
                    blurRadius: 18 * scale,
                    offset: Offset(0, 6 * scale),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size * scale,
            child: badge == null
                ? Icon(icon, size: (iconSize ?? size * 0.55) * scale, color: fg)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(icon, size: (iconSize ?? size * 0.45) * scale, color: fg),
                      Text(
                        badge!,
                        style: TextStyle(
                          fontSize: 9 * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

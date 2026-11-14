import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Gradient-track toggle. Display-only; wrap the row in a tap handler.
class AppSwitch extends StatelessWidget {
  const AppSwitch({required this.on, this.enabled = true, super.key});

  static const double _width = 48;
  static const double _height = 24;
  static const double _inset = 4;
  static const double _track = 16;
  static const double _thumb = 20;

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SizedBox(
        width: _width * scale,
        height: _height * scale,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: _inset * scale,
              right: _inset * scale,
              top: (_height - _track) / 2 * scale,
              height: _track * scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: on
                      ? null
                      : ColorConstants.textOn(dark).withValues(alpha: dark ? 0.08 : 0.1),
                  gradient: on ? BrandColors.of(context).switchGradient : null,
                  borderRadius: BorderRadius.circular(_track * scale / 2),
                ),
              ),
            ),
            AnimatedPositionedDirectional(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: (_height - _thumb) / 2 * scale,
              start: on ? (_width - _inset - _thumb) * scale : _inset * scale,
              child: Container(
                width: _thumb * scale,
                height: _thumb * scale,
                decoration: BoxDecoration(
                  color: dark
                      ? Color.alphaBlend(
                          ColorConstants.white.withValues(alpha: 0.91), ColorConstants.black)
                      : ColorConstants.white,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: ColorConstants.black.withValues(alpha: 0.25),
                      blurRadius: 4 * scale,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

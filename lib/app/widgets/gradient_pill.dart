import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Primary call-to-action: glassy brand gradient with a subtle rim.
class GradientPill extends StatelessWidget {
  const GradientPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 52,
    this.compact = false,
    this.busy = false,
    this.gradient,
    super.key,
  });

  /// Fill instead of the brand gradient (e.g. coral for Watch).
  final LinearGradient? gradient;

  static const double _radius = 12;
  static const double _innerRadius = 11;
  static const double _rim = 1;

  final String label;
  final IconData? icon;
  final double height;
  final bool compact;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final double edge = _rim * scale;
    final LinearGradient gradient = this.gradient ?? BrandColors.of(context).pillGradient;
    final BorderRadius outer = BorderRadius.circular(_radius * scale);
    final BorderRadius inner = BorderRadius.circular(_innerRadius * scale);

    final Widget text = Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontSize: 14 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: ColorConstants.white,
      ),
    );

    final Widget content = busy
        ? Center(
            child: SizedBox.square(
              dimension: 22 * scale,
              child: CircularProgressIndicator(
                strokeWidth: 2.5 * scale,
                color: ColorConstants.white,
              ),
            ),
          )
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 * scale : 0),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20 * scale, color: ColorConstants.white),
                  SizedBox(width: 6 * scale),
                ],
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: text)),
              ],
            ),
          );

    return Opacity(
      opacity: onTap == null && !busy ? 0.5 : 1,
      child: SizedBox(
        height: height * scale,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradient, borderRadius: outer),
          child: Padding(
            padding: EdgeInsets.all(edge),
            child: CustomPaint(
              foregroundPainter: _GlassRim(radius: inner.topLeft.x, width: edge),
              child: Material(
                color: ColorConstants.white.withValues(alpha: 0.03),
                borderRadius: inner,
                clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: busy ? null : onTap, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  const _GlassRim({required this.radius, required this.width});

  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(width / 2), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..blendMode = BlendMode.plus
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[ColorConstants.pillRimTop, ColorConstants.pillRimBottom],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlassRim other) =>
      other.radius != radius || other.width != width;
}

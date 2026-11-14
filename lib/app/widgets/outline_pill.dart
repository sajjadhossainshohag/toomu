import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Secondary action: 1px brand outline, 12 radius.
class OutlinePill extends StatelessWidget {
  const OutlinePill({
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 46,
    this.compact = false,
    this.tone,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  final bool compact;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color tone = this.tone ?? BrandColors.of(context).primary;

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: ColorConstants.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          side: BorderSide(color: tone),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height * scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 * scale : 0),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 18 * scale, color: tone),
                    SizedBox(width: 6 * scale),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: tone,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

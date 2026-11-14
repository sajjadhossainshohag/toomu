import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import 'gradient_pill.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 24 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88 * scale,
              height: 88 * scale,
              decoration: BoxDecoration(
                gradient: BrandColors.of(context).badgeGradient,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: BrandColors.of(context).primary.withValues(alpha: 0.3),
                    blurRadius: 24 * scale,
                    offset: Offset(0, 8 * scale),
                  ),
                ],
              ),
              child: Icon(icon, size: 40 * scale, color: ColorConstants.white),
            ),
            SizedBox(height: 20 * scale),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: ink,
              ),
            ),
            SizedBox(height: 6 * scale),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13 * scale,
                height: 18 / 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: ink.withValues(alpha: 0.6),
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              SizedBox(height: 20 * scale),
              GradientPill(label: actionLabel!, onTap: onAction, compact: true, height: 44),
            ],
          ],
        ),
      ),
    );
  }
}

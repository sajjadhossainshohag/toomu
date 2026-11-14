import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Gradient promo/info card: translucent circular badge + title/message.
class GradientHeroCard extends StatelessWidget {
  const GradientHeroCard({
    required this.icon,
    required this.title,
    required this.message,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(20 * scale),
        decoration: BoxDecoration(
          gradient: BrandColors.of(context).heroGradient,
          borderRadius: BorderRadius.circular(20 * scale),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: ColorConstants.black.withValues(alpha: 0.1),
              blurRadius: 22 * scale,
              offset: Offset(0, 4.4 * scale),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 52 * scale,
              height: 52 * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ColorConstants.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26 * scale, color: ColorConstants.white),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18 * scale,
                      height: 1.26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: ColorConstants.white,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      height: 17 / 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                      color: ColorConstants.white.withValues(alpha: 0.91),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[SizedBox(width: 12 * scale), trailing!],
          ],
        ),
      ),
    );
  }
}

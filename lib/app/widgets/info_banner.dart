import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/design_metrics.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {this.icon, super.key});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = dark ? brand.accent : brand.primary;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
      decoration: BoxDecoration(
        color: brand.primary.withValues(alpha: dark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(12 * scale),
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18 * scale, color: ink),
            SizedBox(width: 10 * scale),
          ],
          Expanded(
            child: Text(
              text,
              textAlign: icon == null ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 13 * scale,
                height: 18 / 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

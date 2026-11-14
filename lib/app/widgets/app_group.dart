import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import 'app_switch.dart';

/// Rounded card grouping several [AppRow]s, separated by page-colored rules.
class AppGroup extends StatelessWidget {
  const AppGroup({required this.rows, this.title, super.key});

  final List<Widget> rows;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignMetrics.gutter * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null) SectionTitle(title!, padded: false),
          Container(
            padding: EdgeInsets.symmetric(vertical: 16 * scale),
            decoration: BoxDecoration(
              color: ColorConstants.groupOn(dark),
              borderRadius: BorderRadius.circular(16 * scale),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 13 * scale),
                      child: Container(height: scale, color: ColorConstants.pageOn(dark)),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: rows[i],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings-style row: tinted rounded glyph tile, label, optional value,
/// toggle or chevron.
class AppRow extends StatelessWidget {
  const AppRow({
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.toggled,
    this.onTap,
    this.showChevron = true,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final bool? toggled;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color muted = ColorConstants.textOn(dark).withValues(alpha: 0.6);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 36 * scale,
        child: Row(
          children: <Widget>[
            GlyphTile(icon: icon, tint: tint),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14 * scale,
                  height: 18 / 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: dark
                      ? ColorConstants.white.withValues(alpha: 0.9)
                      : ColorConstants.lightText,
                ),
              ),
            ),
            if (toggled != null)
              AppSwitch(on: toggled!)
            else ...<Widget>[
              if (value != null) ...<Widget>[
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: muted,
                  ),
                ),
                if (showChevron) SizedBox(width: 8 * scale),
              ],
              if (showChevron)
                SvgPicture.asset(
                  'assets/icons/settings_chevron.svg',
                  matchTextDirection: true,
                  width: 18 * scale,
                  height: 18 * scale,
                  colorFilter:
                      const ColorFilter.mode(ColorConstants.chevron, BlendMode.srcIn),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 36×36 tinted rounded square holding a white glyph.
class GlyphTile extends StatelessWidget {
  const GlyphTile({required this.icon, required this.tint, this.size = 36, super.key});

  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Container(
      width: size * scale,
      height: size * scale,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(size * 0.44 * scale),
      ),
      child: Icon(icon, size: size * 0.5 * scale, color: ColorConstants.white),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, this.padded = true, super.key});

  final String text;
  final Widget? trailing;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padded ? DesignMetrics.gutter * scale : 4 * scale,
        18 * scale,
        padded ? DesignMetrics.gutter * scale : 4 * scale,
        10 * scale,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: ColorConstants.textOn(context.isDark),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

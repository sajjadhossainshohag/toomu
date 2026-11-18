import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

class SheetOption<T> {
  const SheetOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

/// Bottom sheet with a title and options. Without [selected] it is a menu of actions (plain rows); with it,
/// a choice whose current value is checked.
Future<T?> showOptionSheet<T>({
  required String title,
  required List<SheetOption<T>> options,
  T? selected,
}) => Get.bottomSheet<T>(
  AppSheet(
    title: title,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final o in options)
            _OptionRow<T>(
              option: o,
              selected: o.value == selected,
              onTap: () => Get.back(result: o.value),
            ),
        ],
      ),
    ),
  ),
  isScrollControlled: true,
);

/// Sheet chrome: title + content, safe-area aware.
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return ConstrainedBox(
      // Landscape screens are short: keep part of the video visible.
      constraints: BoxConstraints(
        maxHeight: size.height * (landscape ? 0.85 : 0.9),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ColorConstants.surfaceOn(dark),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28 * scale)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20 * scale,
              10 * scale,
              20 * scale,
              16 * scale,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40 * scale,
                    height: 4 * scale,
                    decoration: BoxDecoration(
                      color: ColorConstants.textOn(dark).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2 * scale),
                    ),
                  ),
                ),
                SizedBox(height: (landscape ? 8 : 16) * scale),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          color: ColorConstants.textOn(dark),
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                SizedBox(height: (landscape ? 8 : 12) * scale),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SheetOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = ColorConstants.textOn(dark);

    final Color color = selected ? brand.accent : ink;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12 * scale),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: 13 * scale,
            horizontal: 4 * scale,
          ),
          child: Row(
            children: <Widget>[
              if (option.icon != null) ...<Widget>[
                Icon(
                  option.icon,
                  size: 24 * scale,
                  color: selected ? color : ink.withValues(alpha: 0.85),
                ),
                SizedBox(width: 18 * scale),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 15 * scale,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0,
                        color: color,
                      ),
                    ),
                    if (option.subtitle != null)
                      Text(
                        option.subtitle!,
                        style: TextStyle(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                          color: ink.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 22 * scale, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

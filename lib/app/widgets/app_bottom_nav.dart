import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

class AppNavItem {
  const AppNavItem({required this.label, required this.icon, required this.activeIcon});

  final String label;

  /// Outline icon (inactive) and filled icon (active).
  final IconData icon;
  final IconData activeIcon;
}

/// Floating bottom bar: equal-width slots with icon + one-line label; the
/// active icon sits on a gradient pill (Material 3-style indicator). Slots
/// never change size, so labels can't wrap or jump when switching tabs.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.items,
    required this.index,
    required this.onTap,
    super.key,
  });

  final List<AppNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = ColorConstants.textOn(dark);

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 8 * scale),
        padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 8 * scale),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceOn(dark),
          borderRadius: BorderRadius.circular(22 * scale),
          border: Border.all(color: ink.withValues(alpha: dark ? 0.08 : 0.04)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: brand.primary.withValues(alpha: dark ? 0.10 : 0.12),
              blurRadius: 24 * scale,
              offset: Offset(0, 8 * scale),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _NavSlot(
                  item: items[i],
                  active: i == index,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({required this.item, required this.active, required this.onTap});

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;

  static const _motion = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = ColorConstants.textOn(dark);
    final Color activeInk = dark ? brand.accent : brand.primary;

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 32 * scale,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(16 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: _motion,
              curve: Curves.easeOutCubic,
              width: (active ? 52 : 36) * scale,
              height: 30 * scale,
              decoration: BoxDecoration(
                gradient: active ? brand.pillGradient : null,
                borderRadius: BorderRadius.circular(15 * scale),
                boxShadow: active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: brand.primary.withValues(alpha: 0.35),
                          blurRadius: 10 * scale,
                          offset: Offset(0, 3 * scale),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: _motion,
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Icon(
                  active ? item.activeIcon : item.icon,
                  key: ValueKey<bool>(active),
                  size: 21 * scale,
                  color: active ? ColorConstants.white : ink.withValues(alpha: 0.55),
                ),
              ),
            ),
            SizedBox(height: 4 * scale),
            // One line, never wraps; shrinks a little on very narrow phones.
            SizedBox(
              height: 14 * scale,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0,
                    color: active ? activeInk : ink.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

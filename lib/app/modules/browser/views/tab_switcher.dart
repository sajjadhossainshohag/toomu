import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../controllers/browser_controller.dart';
import '../controllers/browser_session.dart';
import 'site_icon.dart';

/// Incognito's mark (no incognito glyph in Material's set).
const IconData incognitoIcon = Icons.visibility_off_outlined;

/// The tab-count button in the top bar (Chrome's square with a number): the tabs of the shown tab's kind,
/// incognito or normal.
class TabCountButton extends StatelessWidget {
  const TabCountButton({required this.session, super.key});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      final incognito = session.active.value?.incognito ?? false;
      final n = session.tabsOf(incognito: incognito).length;
      return Tooltip(
        message: '$n open ${incognito ? 'incognito ' : ''}${n == 1 ? 'tab' : 'tabs'}',
        child: InkResponse(
          onTap: session.openSwitcher,
          radius: 22 * scale,
          child: SizedBox(
            width: 40 * scale,
            height: 40 * scale,
            child: Center(
              child: Container(
                width: 21 * scale,
                height: 21 * scale,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: ink.withValues(alpha: 0.8), width: 1.8 * scale),
                  borderRadius: BorderRadius.circular(5 * scale),
                ),
                child: Text(
                  n > 99 ? ':D' : '$n',
                  style: TextStyle(
                    fontSize: (n > 9 ? 9.5 : 11.5) * scale,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Chrome's tab grid: a picture of each page, tap to show it, ✕ or swipe
/// to close; new tab and close all at the top.
class TabSwitcher extends StatelessWidget {
  const TabSwitcher({required this.session, super.key});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    return ColoredBox(
      color: ColorConstants.pageOn(dark),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 8 * scale, 4 * scale),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Back',
                  onPressed: () async {
                    if (await session.handleBack()) Get.back<void>();
                  },
                  icon: Icon(Icons.arrow_back_rounded, color: ink),
                ),
                Expanded(
                  child: Obx(() {
                    final incognito = session.switcherIncognito.value;
                    final normal = session.tabsOf(incognito: false).length;
                    final private = session.tabsOf(incognito: true).length;
                    return Row(
                      children: <Widget>[
                        _Kind(
                          label: '$normal ${normal == 1 ? 'tab' : 'tabs'}',
                          selected: !incognito,
                          onTap: () => session.switcherIncognito.value = false,
                        ),
                        SizedBox(width: 6 * scale),
                        _Kind(
                          icon: incognitoIcon,
                          label: '$private',
                          tooltip: 'Incognito tabs',
                          selected: incognito,
                          onTap: () => session.switcherIncognito.value = true,
                        ),
                      ],
                    );
                  }),
                ),
                Obx(() {
                  final incognito = session.switcherIncognito.value;
                  return IconButton(
                    tooltip: incognito ? 'Close all incognito tabs' : 'Close all tabs',
                    onPressed: session.tabsOf(incognito: incognito).isEmpty
                        ? null
                        : () async {
                            final ok = await showConfirmDialog(
                              title: incognito ? 'Close all incognito tabs?' : 'Close all tabs?',
                              message: incognito
                                  ? "Every incognito tab closes, and their cookies and site data are deleted."
                                  : 'Every open tab closes.',
                              confirmLabel: 'Close all',
                              destructive: true,
                            );
                            if (ok) session.closeAll(incognito: incognito);
                          },
                    icon: Icon(Icons.layers_clear_outlined, color: ink.withValues(alpha: 0.8)),
                  );
                }),
                Obx(
                  () => IconButton(
                    tooltip: session.switcherIncognito.value ? 'New incognito tab' : 'New tab',
                    onPressed: session.switcherIncognito.value ? session.newIncognitoTab : session.newTab,
                    icon: Icon(Icons.add_rounded, color: ink),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              final incognito = session.switcherIncognito.value;
              final shown = session.tabsOf(incognito: incognito);
              return shown.isEmpty
                  ? EmptyState(
                      icon: incognito ? incognitoIcon : Icons.tab_rounded,
                      title: incognito ? 'No incognito tabs' : 'No open tabs',
                      message: incognito
                          ? "Pages you open in incognito aren't saved in history, and their cookies and site data "
                                'are deleted when you close the last incognito tab.'
                          : 'Open a new tab to keep browsing, or go back to leave the browser.',
                      actionLabel: incognito ? 'New incognito tab' : 'New tab',
                      onAction: incognito ? session.newIncognitoTab : session.newTab,
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(12 * scale, 4 * scale, 12 * scale, 24 * scale),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
                        mainAxisSpacing: 12 * scale,
                        crossAxisSpacing: 12 * scale,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final t = shown[i];
                        return Dismissible(
                          key: ValueKey(t.id),
                          onDismissed: (_) => session.close(t),
                          child: TabCard(
                            tab: t,
                            selected: t == session.active.value,
                            onTap: () => session.activate(t),
                            onClose: () => session.close(t),
                          ),
                        );
                      },
                    );
            }),
          ),
        ],
      ),
    );
  }
}

/// The switcher's choice between normal and incognito tabs.
class _Kind extends StatelessWidget {
  const _Kind({required this.label, required this.selected, required this.onTap, this.icon, this.tooltip});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final Color primary = BrandColors.of(context).primary;
    final Color color = selected ? primary : ink.withValues(alpha: 0.6);
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18 * scale),
      child: Container(
        height: 34 * scale,
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(18 * scale),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18 * scale, color: color),
              SizedBox(width: 6 * scale),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

class TabCard extends StatelessWidget {
  const TabCard({required this.tab, required this.selected, required this.onTap, required this.onClose, super.key});

  final BrowserController tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final Color primary = BrandColors.of(context).primary;
    return Obx(() {
      final picture = tab.thumbnail.value;
      final newTab = tab.showingNewTab.value;
      return Material(
        color: ColorConstants.surfaceOn(dark),
        borderRadius: BorderRadius.circular(16 * scale),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(color: selected ? primary : ink.withValues(alpha: 0.08), width: selected ? 2.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(10 * scale, 4 * scale, 0, 2 * scale),
                  child: Row(
                    children: <Widget>[
                      if (newTab)
                        Icon(Icons.add_box_outlined, size: 16 * scale, color: ink.withValues(alpha: 0.6))
                      else
                        SiteIcon(url: tab.url.value, size: 16),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          tab.tabTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.w600, color: ink),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close tab',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                        icon: Icon(Icons.close_rounded, size: 17 * scale, color: ink.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: picture != null && !newTab
                      ? Image.memory(picture, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)
                      : ColoredBox(
                          color: ColorConstants.pageOn(dark),
                          child: Center(
                            child: newTab
                                ? Icon(
                                    Icons.travel_explore_rounded,
                                    size: 34 * scale,
                                    color: ink.withValues(alpha: 0.25),
                                  )
                                : SiteIcon(url: tab.url.value, size: 40),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

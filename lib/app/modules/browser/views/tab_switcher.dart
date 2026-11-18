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

/// The tab-count button in the top bar (Chrome's square with a number).
class TabCountButton extends StatelessWidget {
  const TabCountButton({required this.session, super.key});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      final n = session.tabs.length;
      return Tooltip(
        message: '$n open ${n == 1 ? 'tab' : 'tabs'}',
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
                    final n = session.tabs.length;
                    return Text(
                      '$n ${n == 1 ? 'tab' : 'tabs'}',
                      style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.w700, color: ink),
                    );
                  }),
                ),
                Obx(
                  () => IconButton(
                    tooltip: 'Close all tabs',
                    onPressed: session.tabs.isEmpty
                        ? null
                        : () async {
                            final ok = await showConfirmDialog(
                              title: 'Close all tabs?',
                              message: 'Every open tab closes.',
                              confirmLabel: 'Close all',
                              destructive: true,
                            );
                            if (ok) session.closeAll();
                          },
                    icon: Icon(Icons.layers_clear_outlined, color: ink.withValues(alpha: 0.8)),
                  ),
                ),
                IconButton(
                  tooltip: 'New tab',
                  onPressed: session.newTab,
                  icon: Icon(Icons.add_rounded, color: ink),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(
              () => session.tabs.isEmpty
                  ? EmptyState(
                      icon: Icons.tab_rounded,
                      title: 'No open tabs',
                      message: 'Open a new tab to keep browsing, or go back to leave the browser.',
                      actionLabel: 'New tab',
                      onAction: session.newTab,
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(12 * scale, 4 * scale, 12 * scale, 24 * scale),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
                        mainAxisSpacing: 12 * scale,
                        crossAxisSpacing: 12 * scale,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: session.tabs.length,
                      itemBuilder: (_, i) {
                        final t = session.tabs[i];
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
                    ),
            ),
          ),
        ],
      ),
    );
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

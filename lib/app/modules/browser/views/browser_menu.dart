import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/host_os.dart';
import '../controllers/browser_controller.dart';
import '../controllers/browser_session.dart';
import 'bookmarks_page.dart';
import 'downloads_sheet.dart';
import 'history_page.dart';

/// Chrome's ⋮ menu: a row of page buttons (forward, bookmark, share,
/// reload), then the browser's commands.
Future<void> showBrowserMenu(BrowserSession session) => showGeneralDialog<void>(
  context: Get.context!,
  barrierDismissible: true,
  barrierLabel: 'Close menu',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (_, _, _) => BrowserMenu(session: session),
  transitionBuilder: (_, anim, _, child) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      alignment: Alignment.topRight,
      scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

class BrowserMenu extends StatelessWidget {
  const BrowserMenu({required this.session, super.key});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final BrowserController tab = session.tab;
    final bool page = !tab.showingNewTab.value;

    void run(VoidCallback action) {
      Get.back<void>();
      action();
    }

    Widget item(IconData icon, String label, VoidCallback? onTap, {Widget? trailing}) => InkWell(
      onTap: onTap == null ? null : () => run(onTap),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 13 * scale),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 21 * scale,
              color: ink.withValues(alpha: onTap == null ? 0.3 : 0.75),
            ),
            SizedBox(width: 18 * scale),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5 * scale,
                  fontWeight: FontWeight.w500,
                  color: ink.withValues(alpha: onTap == null ? 0.35 : 1),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );

    Widget top(IconData icon, String tooltip, VoidCallback? onTap, {bool on = false}) => Expanded(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap == null ? null : () => run(onTap),
        icon: Icon(
          icon,
          size: 22 * scale,
          color: on ? BrandColors.of(context).primary : ink.withValues(alpha: onTap == null ? 0.25 : 0.8),
        ),
      ),
    );

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: 6 * scale, right: 6 * scale),
          child: Material(
            color: ColorConstants.surfaceOn(dark),
            elevation: 8,
            shadowColor: ColorConstants.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16 * scale),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 264 * scale, maxHeight: MediaQuery.sizeOf(context).height - 40),
              child: SingleChildScrollView(
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                        child: Row(
                          children: <Widget>[
                            top(
                              Icons.arrow_forward_rounded,
                              'Forward',
                              tab.canGoForward.value && page ? tab.goForward : null,
                            ),
                            top(
                              tab.bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                              tab.bookmarked ? 'Edit bookmark' : 'Bookmark',
                              page ? tab.toggleBookmark : null,
                              on: tab.bookmarked,
                            ),
                            top(Icons.share_outlined, 'Share', page ? tab.sharePage : null),
                            tab.loading
                                ? top(Icons.close_rounded, 'Stop', tab.stop)
                                : top(Icons.refresh_rounded, 'Reload', page ? tab.reload : null),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: ink.withValues(alpha: 0.08)),
                      SizedBox(height: 4 * scale),
                      item(Icons.add_box_outlined, 'New tab', session.newTab),
                      item(Icons.history_rounded, 'History', () => Get.to<void>(() => HistoryPage(session: session))),
                      item(
                        Icons.star_outline_rounded,
                        'Bookmarks',
                        () => Get.to<void>(() => BookmarksPage(session: session)),
                      ),
                      item(Icons.download_outlined, 'Downloads', showDownloadsSheet),
                      item(Icons.link_rounded, 'Copy link', page ? tab.copyPageLink : null),
                      // Android's WebView finds text in the page; Windows' has its own Ctrl+F.
                      if (HostOs.isAndroid)
                        item(Icons.find_in_page_outlined, 'Find in page', page ? tab.startFind : null),
                      // Windows already gets desktop pages.
                      if (!HostOs.isWindows)
                        item(
                          Icons.desktop_windows_outlined,
                          'Desktop site',
                          tab.toggleDesktop,
                          trailing: SizedBox(
                            width: 22 * scale,
                            height: 22 * scale,
                            child: Checkbox(
                              value: tab.desktop.value,
                              onChanged: (_) => run(tab.toggleDesktop),
                              activeColor: BrandColors.of(context).primary,
                            ),
                          ),
                        ),
                      SizedBox(height: 4 * scale),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

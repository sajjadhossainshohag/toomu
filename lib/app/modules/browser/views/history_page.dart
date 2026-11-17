import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/browser_store.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/outline_pill.dart';
import '../browsing_data.dart';
import '../controllers/browser_session.dart';
import 'site_icon.dart';

/// Chrome's History: pages by day, search, remove one, or clear browsing
/// data.
class HistoryPage extends StatefulWidget {
  const HistoryPage({required this.session, super.key});

  final BrowserSession session;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = ''.obs;

  @override
  Widget build(BuildContext context) {
    final store = BrowserStore.to;
    final bool dark = context.isDark;
    return Scaffold(
      backgroundColor: ColorConstants.pageOn(dark),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AppHeader(
              title: 'History',
              onBack: Get.back,
              actions: <Widget>[
                HeaderAction(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: 'Clear browsing data',
                  onTap: clearBrowsingData,
                ),
              ],
              bottom: AppSearchField(hint: 'Search history', onChanged: (v) => _query.value = v),
            ),
            Expanded(
              child: Obx(() {
                store.historyVersion.value;
                final visits = store.history.search(_query.value);
                if (visits.isEmpty) {
                  return EmptyState(
                    icon: Icons.history_rounded,
                    title: _query.value.isEmpty ? 'No history yet' : 'Nothing found',
                    message: _query.value.isEmpty ? 'Pages you visit show up here.' : 'Try other words.',
                  );
                }
                final groups = store.history.byDay(visits, DateTime.now());
                return ListView(
                  padding: EdgeInsets.only(bottom: 24 * context.scale),
                  children: <Widget>[
                    for (final g in groups) ...<Widget>[
                      PageListLabel(g.label),
                      for (final v in g.visits)
                        PageRow(
                          visit: v,
                          trailing: _time(v.at),
                          onTap: () => _open(v.url),
                          onRemove: () => store.removeVisit(v),
                        ),
                    ],
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _open(String url) {
    Get.back<void>();
    widget.session.tab.navigate(url);
  }
}

/// Chrome's "Clear browsing data": history, cookies and site data, cached
/// files — each optional.
Future<void> clearBrowsingData() async {
  var history = true;
  var cookies = false;
  var cache = true;
  final ok = await showAppDialog<bool>(
    title: 'Clear browsing data',
    child: StatefulBuilder(
      builder: (context, setState) {
        final double scale = context.scale;
        Widget option(String label, String detail, bool value, ValueChanged<bool> set) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => set(!value)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8 * scale),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 12 * scale, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                AppSwitch(on: value),
              ],
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            option('Browsing history', 'Pages you visited', history, (v) => history = v),
            option('Cookies and site data', 'Signs you out of most sites', cookies, (v) => cookies = v),
            option('Cached images and files', 'Frees space; sites load slower next time', cache, (v) => cache = v),
            SizedBox(height: 16 * scale),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinePill(label: 'Cancel', height: 40, onTap: () => Get.back(result: false)),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: GradientPill(label: 'Clear', height: 40, onTap: () => Get.back(result: true)),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !(history || cookies || cache)) return;
  if (history) BrowserStore.to.clearHistory();
  try {
    if (cookies) {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
    }
    if (cache) await InAppWebViewController.clearAllCache();
  } catch (_) {
    // Partly cleared is still cleared; the rest needs a WebView open.
  }
  showSnack('Browsing data cleared', [if (history) 'History', if (cookies) 'Cookies', if (cache) 'Cache'].join(', '));
}

/// Day heading in History, section heading in Bookmarks.
class PageListLabel extends StatelessWidget {
  const PageListLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * scale, 16 * scale, 20 * scale, 6 * scale),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13 * scale,
          fontWeight: FontWeight.w700,
          color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// One page in History or Bookmarks: its icon, title and site.
class PageRow extends StatelessWidget {
  const PageRow({required this.visit, required this.onTap, required this.onRemove, this.trailing, super.key});

  final PageVisit visit;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20 * scale, 10 * scale, 8 * scale, 10 * scale),
        child: Row(
          children: <Widget>[
            SiteIcon(url: visit.url, size: 26),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    visit.title.isEmpty ? visit.bare : visit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w500, color: ink),
                  ),
                  Text(
                    [Uri.tryParse(visit.url)?.host ?? '', ?trailing].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, size: 18 * scale, color: ink.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }
}

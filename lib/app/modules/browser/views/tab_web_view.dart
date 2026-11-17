import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/utils/host_os.dart';
import '../controllers/browser_controller.dart';

/// The web page of one tab. Each page gets its own pull-to-refresh and
/// find-in-page helpers (the plugin ties them to one WebView).
class TabWebView extends StatefulWidget {
  const TabWebView({required this.tab, super.key});

  final BrowserController tab;

  @override
  State<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends State<TabWebView> {
  PullToRefreshController? _pull;
  late final FindInteractionController _find;

  /// The page's scripts, built when its WebView is made (it reads them
  /// only then), fresh for each page.
  late final _scripts = c.userScripts;

  BrowserController get c => widget.tab;

  @override
  void initState() {
    super.initState();
    // Pull down to reload (Android; Windows' WebView2 has no such gesture).
    if (HostOs.isAndroid) {
      _pull = PullToRefreshController(
        settings: PullToRefreshSettings(color: ColorConstants.primary),
        onRefresh: () => c.web?.reload(),
      );
    }
    _find = FindInteractionController(onFindResultReceived: (_, active, total, _) => c.onFindResult(active, total));
    c.attach(pullToRefresh: _pull, find: _find);
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(c.restoreUrl)),
    initialSettings: c.settings,
    initialUserScripts: _scripts,
    pullToRefreshController: _pull,
    findInteractionController: _find,
    onWebViewCreated: c.onCreated,
    onLoadStart: (_, url) => c.onLoadStart(url),
    onLoadStop: (_, _) => c.onLoadStop(),
    onReceivedError: (_, request, error) => c.onLoadError(request, error),
    onReceivedServerTrustAuthRequest: (_, challenge) => c.onCertificateError(challenge),
    onScrollChanged: (_, _, y) => c.onScroll(y),
    onUpdateVisitedHistory: (_, url, _) => c.onHistoryChanged(url),
    onTitleChanged: (_, t) => c.onTitle(t),
    onProgressChanged: (_, p) => c.onProgress(p),
    shouldOverrideUrlLoading: (_, action) async => c.onNavigate(action),
    onDownloadStartRequest: (_, request) => c.onDownloadStart(request),
    onLongPressHitTestResult: (_, hit) => c.onLongPress(hit),
    shouldInterceptRequest: c.blockAds ? (_, request) => c.onRequest(request) : null,
    onRenderProcessGone: (_, _) => c.onRendererGone(),
  );
}

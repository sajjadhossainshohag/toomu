import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/device_profile.dart';
import '../../../core/utils/host_os.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/media_manifest.dart';
import '../../../data/models/captured_media.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/media_format.dart';
import '../../../data/models/video_item.dart';
import '../../../data/models/yt_info.dart';
import '../../../extractors/direct_file_extractor.dart';
import '../../../extractors/extractors.dart';
import '../../../routes/app_pages.dart';
import '../../../services/browser_store.dart';
import '../../../services/download_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/ytdlp_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/option_sheet.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../ad_blocker.dart';
import '../address.dart';
import '../engine_notice.dart';
import '../incognito.dart';
import '../link_menu.dart';
import '../tab_session.dart';
import '../image_menu.dart';
import '../media_button.dart';
import '../media_capture.dart';
import '../media_title.dart';
import '../media_sniffer.dart';
import '../redirect_guard.dart';
import '../views/downloads_sheet.dart';
import '../views/image_menu_dialog.dart';
import '../views/image_preview_page.dart';
import '../views/media_sheet.dart';

/// One browser tab. Sites load in a real WebView (real cookies and
/// session, like any mobile browser); when the current page is something
/// an extractor supports, the Download button appears. BrowserSession
/// owns the tabs.
class BrowserController extends GetxController {
  BrowserController({String url = newTabUrl, this.refreshFor, String? id, this.incognito = false})
    : initialUrl = refreshFor?.pageUrl ?? url,
      id = id ?? newTabId();

  final String id;

  /// An incognito tab: its own cookies and site data (see [Incognito]), no history, not brought back next time.
  final bool incognito;

  /// Android: the page waits until the WebView is in the incognito profile (its first load would use normal
  /// tabs' cookies), so the WebView starts empty and [onCreated] loads it.
  bool get loadsAfterCreated => incognito && HostOs.isAndroid;

  /// Set by the session: opens [url] in a new incognito tab.
  void Function(String url)? openIncognito;

  /// Set by the session: closes this tab.
  VoidCallback? closeTab;

  // Opened from a download whose link expired: find the same file again.
  final DownloadTask? refreshFor;

  final String initialUrl;

  /// Set by the session: opens [url] in another tab.
  void Function(String url, {required bool background})? openTab;

  /// Set by the session: this tab's "Refresh link" errand is done.
  VoidCallback? onRefreshed;

  /// This tab is the one shown (others are paused in the background).
  bool foreground = true;

  /// Chrome's new-tab page is showing (a Flutter screen, no web page).
  final showingNewTab = false.obs;

  /// Back from the first page returns to the new-tab page it came from.
  bool _cameFromNewTab = false;

  /// What the tab switcher shows for this tab.
  String get tabTitle =>
      showingNewTab.value ? 'New tab' : (title.value.isNotEmpty ? title.value : displayAddress(url.value));
  String get tabUrl => showingNewTab.value ? newTabUrl : url.value;

  /// Picture of the page for the tab switcher (taken when leaving it).
  final thumbnail = Rxn<Uint8List>();

  final desktop = false.obs;
  final addressFocused = false.obs;
  final addressFocus = FocusNode();

  /// The top bar slides away while reading (scrolling down), like Chrome's.
  final barShown = true.obs;
  final suggestions = <Suggestion>[].obs;

  /// Android 7–9: why the page didn't load (old web engine), or null.
  final engineNotice = RxnString();

  // Find in page.
  FindInteractionController? findController;
  final finding = false.obs;
  final findMatches = (active: 0, total: 0).obs;

  bool get loading => progress.value < 1 && !showingNewTab.value;

  final address = TextEditingController();
  final url = ''.obs;
  final title = ''.obs;
  final progress = 0.0.obs;
  final canGoBack = false.obs;
  final canGoForward = false.obs;
  final extractor = Rxn<MediaExtractor>();
  final capture = MediaCapture();
  final guard = RedirectGuard();
  final bool _blockRedirects = SettingsService.to.blockRedirects.value;
  final bool blockAds = SettingsService.to.blockAds.value;
  late final adBlocker = AdBlocker(allowedSites: () => SettingsService.to.adsAllowedSites);

  /// Ad requests stopped on the current page.
  final adsBlocked = 0.obs;
  String? _allowNext;
  String _lastBlocked = '';
  DateTime _lastBlockedAt = DateTime(0);

  final webKey = 0.obs;
  String restoreUrl = '';

  final pageResult = Rxn<YtInfo>();
  final searching = false.obs;
  final searchError = RxnString();
  String _searchedUrl = '';
  bool _refreshed = false;

  InAppWebViewController? web;
  AppLifecycleListener? _lifecycle;

  late final settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    useOnDownloadStart: true, // 1DM-style: catch file downloads
    useOnRenderProcessGone: true,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    supportZoom: false,
    useShouldOverrideUrlLoading: true,
    // Popups then open in this tab, where onNavigate can block them.
    supportMultipleWindows: false,
    // Ad blocking asks about every request (Android only; Windows' WebView2
    // gets the ad-hiding style alone).
    useShouldInterceptRequest: blockAds && Platform.isAndroid,
    // Windows: WebView2's InPrivate mode (Android uses a WebView profile, see Incognito).
    incognito: incognito && HostOs.isWindows,
  );

  /// Built for each new WebView (a dropped tab's page is rebuilt later):
  /// a list kept from the first one would miss filters loaded since, and
  /// sites allowed in another tab. Cheap: the big ad script is shared.
  UnmodifiableListView<UserScript> get userScripts => UnmodifiableListView<UserScript>([
    if (blockAds) _adHidingScript(),
    if (SettingsService.to.captureMedia.value)
      UserScript(
        source: mediaSnifferJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    if (SettingsService.to.blockRedirects.value)
      UserScript(
        source: tapRecorderJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
  ]);

  @override
  void onInit() {
    super.onInit();
    url.value = initialUrl;
    showingNewTab.value = isNewTab(initialUrl);
    _cameFromNewTab = showingNewTab.value;
    restoreUrl = showingNewTab.value ? '' : initialUrl;
    address.text = displayAddress(initialUrl);
    capture.onFound = _maybeRefresh;
    capture.pageTitle = () => title.value;
    capture.pageUrl = () => url.value;
    // Something new found: show the button even mid-scroll.
    ever(capture.items, (_) {
      if (capture.items.isNotEmpty) mediaButtonShown.value = true;
    });
    _detect(initialUrl);
    if (_blockRedirects || blockAds) unawaited(Blocklist.load());
    // EasyList: the hiding stylesheet follows once it's read.
    if (blockAds) unawaited(AdFilters.load().then((_) => _refreshAdScript(reload: false)));
  }

  @override
  void onClose() {
    _imageDioOrNull?.close(force: true);
    _suggestDioOrNull?.close(force: true);
    _suggestTimer?.cancel();
    _suggestCancel?.cancel();
    capture.dispose();
    _lifecycle?.dispose();
    address.dispose();
    addressFocus.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------- WebView hooks

  void onCreated(InAppWebViewController c) {
    web = c;
    // Pause the page while the app is hidden: only tabs with a page need it
    // (most of 30 restored tabs never get one).
    if (Platform.isAndroid) {
      _lifecycle ??= AppLifecycleListener(onHide: () => unawaited(_run(false)), onShow: () => unawaited(_run(true)));
    }
    _loading(restoreUrl);
    if (loadsAfterCreated) unawaited(_loadIncognito(c));
    if (blockAds) {
      c.addJavaScriptHandler(
        handlerName: 'toomuCss',
        callback: (List<dynamic> args) {
          final frame = args.isEmpty ? url.value : '${args.first}';
          final h = adBlocker.hidingFor(frame, pageUrl: url.value);
          return {'generic': h.generic, 'css': h.css};
        },
      );
    }
    c.addJavaScriptHandler(
      handlerName: 'toomuMedia',
      callback: (List<dynamic> args) {
        final m = args.isEmpty ? null : args.first;
        if (m is Map) capture.onReport(Map<String, dynamic>.from(m));
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'toomuTap',
      callback: (List<dynamic> args) {
        guard.onTap(args.isEmpty ? '' : '${args.first}');
        return null;
      },
    );
  }

  Future<void> _loadIncognito(InAppWebViewController c) async {
    if (!await Incognito.attach(c)) {
      showSnack(
        "Couldn't open an incognito tab",
        'Update "Android System WebView" from the Play Store, then try again.',
        duration: const Duration(seconds: 5),
      );
      closeTab?.call();
      return;
    }
    if (identical(web, c) && restoreUrl.isNotEmpty) await c.loadUrl(urlRequest: URLRequest(url: WebUri(restoreUrl)));
  }

  /// Cookies the page's site set, for a download from this tab.
  Future<String> _cookies(String url) =>
      incognito ? Incognito.cookies(url, web) : DownloadService.webCookies(url);

  void onLoadStart(WebUri? u) {
    if (u != null) _loading(u.toString());
    engineNotice.value = null;
    adsBlocked.value = 0;
    _scroll.reset();
    mediaButtonShown.value = true;
    barShown.value = true;
    capture.reset();
    pageResult.value = null;
    searchError.value = null;
  }

  /// YouTube is a single-page app: video changes arrive as history updates,
  /// not page loads, so detection hangs off this callback.
  Future<void> onHistoryChanged(WebUri? u) async {
    if (u == null) return;
    url.value = u.toString();
    restoreUrl = url.value;
    if (!_editingAddress) address.text = displayAddress(url.value);
    _detect(url.value);
    // The title may have come before the address (see onTitle): ask the
    // page. If it comes after, onTitle sets it then.
    final page = url.value;
    if (!incognito) {
      BrowserStore.to.visit(page, '');
      try {
        final t = await web?.getTitle();
        if (t != null && t.isNotEmpty) BrowserStore.to.retitle(page, t);
      } catch (_) {}
    }
    canGoBack.value = await web?.canGoBack() ?? false;
    canGoForward.value = await web?.canGoForward() ?? false;
  }

  void onRendererGone() {
    // Android can't reuse a WebView whose renderer died: build a new one at
    // the same page instead of leaving a white screen.
    debugPrint('[Browser] renderer gone; reopening $restoreUrl');
    web = null;
    webKey.value++;
  }

  // ---------------------------------------------------------------- ad blocking

  static final _nothing = WebResourceResponse(
    contentType: 'text/plain',
    data: Uint8List(0),
    statusCode: 204,
    reasonPhrase: 'No Content',
    headers: const {'Access-Control-Allow-Origin': '*'},
  );

  /// A request from the page (images, scripts, frames…): ad hosts get an
  /// empty answer. The page's own navigation is never stopped here.
  Future<WebResourceResponse?> onRequest(WebResourceRequest request) async {
    if (request.isForMainFrame ?? false) return null;
    final type = AdBlocker.typeOf(request.url, request.headers);
    if (!adBlocker.blocks(request.url, pageUrl: url.value, type: type)) return null;
    adsBlocked.value++;
    return _nothing;
  }

  UserScript _adHidingScript() => UserScript(
    groupName: 'toomuAds',
    source: adHidingJsFor(SettingsService.to.adsAllowedSites.toSet(), genericCss: AdFilters.engine?.genericCss ?? ''),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    // EasyList's general stylesheet is ~0.5 MB: once per page, not per
    // frame (ad frames' own requests are blocked anyway).
    forMainFrameOnly: true,
  );

  /// The site of the open page ("example.com").
  String get site => AdBlocker.siteOf(url.value);

  bool get adsAllowedHere => adBlocker.allowedOn(url.value);

  /// Shield button: ads on / off for this site, then reload to apply.
  Future<void> showAdMenu() async {
    final here = site;
    if (here.isEmpty) return;
    final allow = await showOptionSheet<bool>(
      title: here,
      selected: adsAllowedHere,
      options: [
        SheetOption(
          value: false,
          label: 'Block ads on this site',
          subtitle: adsBlocked.value > 0 ? '${adsBlocked.value} blocked on this page' : null,
          icon: Icons.shield_rounded,
        ),
        const SheetOption(
          value: true,
          label: 'Allow ads on this site',
          subtitle: 'If the site doesn\'t work with ads blocked',
          icon: Icons.shield_outlined,
        ),
      ],
    );
    if (allow == null || allow == adsAllowedHere) return;
    SettingsService.to.setAdsAllowed(here, allow);
    await _refreshAdScript(reload: true);
  }

  /// New ad-hiding script (allowed sites or EasyList changed); applies from
  /// the next page load, or now with [reload].
  Future<void> _refreshAdScript({required bool reload}) async {
    final c = web;
    if (c == null || isClosed) return;
    await c.removeUserScriptsByGroupName(groupName: 'toomuAds');
    await c.addUserScript(userScript: _adHidingScript());
    if (reload) await c.reload();
  }

  /// A single-page site can set its new title before telling us its new
  /// address: the title goes to the page the WebView actually shows, not
  /// the last address we heard of.
  Future<void> onTitle(String? t) async {
    title.value = t ?? '';
    if (incognito) return;
    final shown = title.value;
    String page = url.value;
    try {
      page = (await web?.getUrl())?.toString() ?? page;
    } catch (_) {}
    BrowserStore.to.retitle(page, shown);
  }

  void onLoadStop() => _pullToRefresh?.endRefreshing();

  /// A page that didn't load. On Android 7–9 this may be the phone's old
  /// web engine: say so instead of leaving a bare error page.
  Future<void> onLoadError(WebResourceRequest request, WebResourceError error) async {
    if (!(request.isForMainFrame ?? true)) return;
    await _pullToRefresh?.endRefreshing();
    if (!HostOs.isAndroid || DeviceProfile.androidSdk >= updatedEngineSdk) return;
    engineNotice.value = outdatedEngineNotice(
      androidSdk: DeviceProfile.androidSdk,
      webViewVersion: await _webViewVersion(),
      errorType: error.type.toString(),
    );
  }

  /// The site the page is loading from: set as soon as a load begins (a
  /// certificate error can come before onLoadStart, or instead of it).
  String _loadingHost = '';

  void _loading(String target) => _loadingHost = Uri.tryParse(target)?.host.toLowerCase() ?? '';

  /// The site's certificate isn't trusted. On Android 7–9 that's usually
  /// the phone's outdated certificates, not the site: say so for the page
  /// itself (not for an ad or image from elsewhere). The page stays
  /// blocked, as before.
  Future<ServerTrustAuthResponse> onCertificateError(URLAuthenticationChallenge challenge) async {
    final host = challenge.protectionSpace.host.toLowerCase();
    if (host == _loadingHost && HostOs.isAndroid && DeviceProfile.androidSdk < updatedEngineSdk) {
      engineNotice.value = outdatedEngineNotice(
        androidSdk: DeviceProfile.androidSdk,
        webViewVersion: await _webViewVersion(),
        errorType: 'FAILED_SSL_HANDSHAKE',
      );
    }
    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL);
  }

  static String? _engineVersion;

  static Future<String> _webViewVersion() async {
    try {
      return _engineVersion ??= (await InAppWebViewController.getCurrentWebViewPackage())?.versionName ?? '';
    } catch (_) {
      return '';
    }
  }

  PullToRefreshController? _pullToRefresh;

  /// The WebView widget made these for its page (new ones per page).
  void attach({PullToRefreshController? pullToRefresh, FindInteractionController? find}) {
    _pullToRefresh = pullToRefresh;
    findController = find;
  }

  void onFindResult(int active, int total) => findMatches.value = (active: total == 0 ? 0 : active + 1, total: total);

  void onProgress(int p) => progress.value = p / 100;

  /// Opens app links (intent://, market://) outside instead of erroring.
  NavigationActionPolicy onNavigate(NavigationAction action) {
    final target = action.request.url;
    final scheme = target?.scheme ?? 'https';
    if (scheme != 'http' && scheme != 'https' && scheme != 'about' && scheme != 'data') {
      return NavigationActionPolicy.CANCEL;
    }
    if (target != null && action.isForMainFrame) _loading(target.toString());
    if (target == null || !_blockRedirects || !action.isForMainFrame || !scheme.startsWith('http')) {
      return NavigationActionPolicy.ALLOW;
    }
    if (target.toString() == _allowNext) {
      _allowNext = null;
      return NavigationActionPolicy.ALLOW;
    }
    if (!guard.blocks(from: url.value, to: target, redirect: action.isRedirect ?? false)) {
      return NavigationActionPolicy.ALLOW;
    }
    _showBlocked(target.toString(), target.host);
    return NavigationActionPolicy.CANCEL;
  }

  void _showBlocked(String target, String host) {
    debugPrint('[Browser] blocked redirect to $host');
    final now = DateTime.now();
    if (host == _lastBlocked && now.difference(_lastBlockedAt) < const Duration(seconds: 4)) return;
    _lastBlocked = host;
    _lastBlockedAt = now;
    showSnack(
      'Blocked redirect',
      host,
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () {
          Get.closeCurrentSnackbar();
          _open(target);
        },
        child: const Text('Open'),
      ),
    );
  }

  void _open(String target) {
    // Some platforms ask shouldOverrideUrlLoading about loadUrl too.
    _allowNext = target;
    _loading(target);
    web?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  /// A link the site serves as a file download.
  Future<void> onDownloadStart(DownloadStartRequest request) async {
    final ua = request.userAgent ?? capture.userAgent;
    final link = request.url.toString();
    return DirectFileExtractor.startDownload(
      link,
      fileName: downloadName(
        suggested: request.suggestedFilename,
        url: link,
        pageTitle: title.value,
        pageUrl: url.value,
        contentDisposition: request.contentDisposition,
        pageHints: await _pageNameHints(),
      ),
      size: request.contentLength,
      pageUrl: url.value,
      headers: {if (ua.isNotEmpty) 'User-Agent': ua, 'Referer': url.value},
      mimeType: request.mimeType,
    );
  }

  // File pages titled "Download" or the site's name still show the file's name in their share title or heading.
  Future<List<String>> _pageNameHints() async {
    try {
      final r = await web
          ?.evaluateJavascript(
            source:
                '(function(){function q(s){var e=document.querySelector(s);'
                'return e?String(e.content||e.textContent||"").trim().slice(0,300):"";}'
                'return JSON.stringify([q("meta[property=og\\:title]"),q("h1")]);})()',
          )
          .timeout(const Duration(milliseconds: 600));
      return r is String ? (jsonDecode(r) as List).cast<String>() : const [];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------------ actions

  bool _editingAddress = false;

  /// URL → open it; anything else → search (YouTube when on YouTube).
  void submit(String input) {
    final text = input.trim();
    if (text.isEmpty) return;
    navigate(addressTarget(text, currentUrl: showingNewTab.value ? '' : url.value));
  }

  /// Loads [target] in this tab (the first page of a new tab builds its
  /// WebView).
  void navigate(String target) {
    _editingAddress = false;
    addressFocused.value = false;
    suggestions.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    if (isNewTab(target)) return showNewTabPage();
    showingNewTab.value = false;
    address.text = displayAddress(target);
    if (web != null) {
      _open(target);
      return;
    }
    url.value = target;
    restoreUrl = target;
    _detect(target);
    webKey.value++;
  }

  void showNewTabPage() {
    showingNewTab.value = true;
    address.clear();
    unawaited(_pausePage());
  }

  /// Address bar tapped: the whole address, selected (Chrome); left: the
  /// site again.
  void onAddressFocus(bool focused) {
    _editingAddress = focused;
    addressFocused.value = focused;
    if (focused) {
      address.text = showingNewTab.value ? '' : url.value;
      address.selection = TextSelection(baseOffset: 0, extentOffset: address.text.length);
    } else {
      address.text = showingNewTab.value ? '' : displayAddress(url.value);
      suggestions.clear();
      _suggestTimer?.cancel();
    }
  }

  Dio? _suggestDioOrNull;
  Dio get _suggestDio => _suggestDioOrNull ??= Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
  );
  Timer? _suggestTimer;
  CancelToken? _suggestCancel;

  /// Typing in the address bar: bookmarks and history at once, Google's
  /// suggestions as they arrive.
  void onAddressChanged(String text) {
    final store = BrowserStore.to;
    List<Suggestion> local(List<String> searches) => mergeSuggestions(
      text,
      bookmarks: store.bookmarks.search(text).take(3).toList(),
      history: store.history.suggest(text, 4),
      searches: searches,
      currentUrl: showingNewTab.value ? '' : url.value,
    );
    suggestions.assignAll(local(const []));
    _suggestTimer?.cancel();
    _suggestCancel?.cancel();
    if (text.trim().isEmpty || looksLikeAddress(text)) return;
    _suggestTimer = Timer(const Duration(milliseconds: 150), () async {
      final cancel = _suggestCancel = CancelToken();
      try {
        final r = await _suggestDio.get<dynamic>(
          'https://suggestqueries.google.com/complete/search',
          // UTF-8 both ways, or Bangla and other scripts come back garbled.
          queryParameters: {'client': 'firefox', 'ie': 'utf-8', 'oe': 'utf-8', 'q': text},
          cancelToken: cancel,
          options: Options(responseType: ResponseType.plain),
        );
        if (cancel.isCancelled || !addressFocused.value || address.text != text) return;
        suggestions.assignAll(local(parseGoogleSuggest(jsonDecode('${r.data}'))));
      } catch (_) {
        // Offline or refused: the local suggestions stay.
      }
    });
  }

  // ----------------------------------------------------------- menu actions

  void stop() => web?.stopLoading();

  Future<void> sharePage() async {
    if (showingNewTab.value) return;
    await SharePlus.instance.share(ShareParams(uri: Uri.tryParse(url.value), subject: title.value));
  }

  Future<void> copyPageLink() async {
    await Clipboard.setData(ClipboardData(text: url.value));
    showSnack('Link copied', displayAddress(url.value), duration: const Duration(seconds: 2));
  }

  bool get bookmarked {
    BrowserStore.to.bookmarksVersion.value; // rebuild on change
    return !showingNewTab.value && BrowserStore.to.bookmarks.has(url.value);
  }

  void toggleBookmark() {
    if (showingNewTab.value) return;
    final on = BrowserStore.to.toggleBookmark(url.value, title.value);
    showSnack(on ? 'Bookmarked' : 'Bookmark removed', tabTitle, duration: const Duration(seconds: 2));
  }

  /// "Desktop site": desktop Chrome's User-Agent and a wide page, then reload.
  Future<void> toggleDesktop() async {
    desktop.toggle();
    settings
      // '' = the phone's own User-Agent for a WebView made later.
      ..userAgent = desktop.value ? desktopUserAgent : ''
      ..preferredContentMode = desktop.value ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.RECOMMENDED
      ..useWideViewPort = true
      ..loadWithOverviewMode = desktop.value;
    final w = web;
    if (w == null) return;
    // A live page ignores an empty User-Agent (the plugin skips it), so
    // "Desktop site" off must name the phone's own one.
    final live = settings.copy()..userAgent = desktop.value ? desktopUserAgent : await _phoneUserAgent();
    await w.setSettings(settings: live);
    final wide = desktop.value ? desktopAddress(url.value) : null;
    if (wide != null) {
      // Mobile hosts (m.facebook.com) ignore the User-Agent: open the desktop host.
      await w.loadUrl(urlRequest: URLRequest(url: WebUri(wide)));
    } else {
      await w.reload();
    }
  }

  static String? _defaultUa;

  static Future<String> _phoneUserAgent() async {
    try {
      return _defaultUa ??= await InAppWebViewController.getDefaultUserAgent();
    } catch (_) {
      return '';
    }
  }

  void startFind() {
    if (showingNewTab.value || findController == null) return;
    finding.value = true;
    findMatches.value = (active: 0, total: 0);
  }

  Future<void> find(String text) async {
    if (text.isEmpty) {
      findMatches.value = (active: 0, total: 0);
      return findController?.clearMatches();
    }
    await findController?.findAll(find: text);
  }

  Future<void> findNext({bool forward = true}) async => findController?.findNext(forward: forward);

  Future<void> stopFind() async {
    finding.value = false;
    await findController?.clearMatches();
  }

  /// Picture of the page for the tab switcher.
  Future<void> snapshot() async {
    final w = web;
    if (w == null || showingNewTab.value) return;
    try {
      final png = await w
          .takeScreenshot(
            screenshotConfiguration: ScreenshotConfiguration(
              compressFormat: CompressFormat.JPEG,
              quality: 45,
              snapshotWidth: 360,
            ),
          )
          .timeout(const Duration(seconds: 1));
      if (png != null) setThumbnail(png);
    } catch (_) {}
  }

  /// Replaces the switcher picture; the old one leaves Flutter's image
  /// cache now (decoded, it is ~1 MB) instead of when the cache fills up.
  void setThumbnail(Uint8List? picture) {
    final old = thumbnail.value;
    if (old != null && !identical(old, picture)) unawaited(MemoryImage(old).evict());
    thumbnail.value = picture;
  }

  /// Shown or sent to the background (its video stops, like Chrome).
  Future<void> setForeground(bool on) async {
    foreground = on;
    final w = web;
    if (w == null) return;
    if (on) {
      if (HostOs.isAndroid) await w.resume();
    } else {
      await _pausePage();
      if (HostOs.isAndroid) await w.pause();
    }
  }

  /// Its page was dropped to save memory; it reloads when shown again.
  void dropPage() {
    web = null;
    findController = null;
    _pullToRefresh = null;
  }

  MediaButtonMode get mediaButton =>
      mediaButtonMode(supportedPage: extractor.value != null, found: capture.items.length, canScan: HostOs.hasYtDlp);

  /// The media button slides away while reading (scrolling down).
  final mediaButtonShown = true.obs;
  final _scroll = ScrollHider();

  DateTime _barMovedAt = DateTime(0);

  void onScroll(int y) {
    // Showing or hiding the bar resizes the page; at its bottom that moves
    // the scroll position by the bar's height, which must not count as the
    // reader scrolling back (the bar would flicker in and out).
    if (DateTime.now().difference(_barMovedAt) < const Duration(milliseconds: 350)) {
      _scroll.rebase(y);
      return;
    }
    final shown = _scroll.update(y);
    mediaButtonShown.value = shown;
    if (barShown.value != shown) {
      barShown.value = shown;
      _barMovedAt = DateTime.now();
    }
  }

  Future<void> onFab() async {
    if (extractor.value != null) return download();
    await _pausePage();
    await showMediaSheet(this);
  }

  Future<void> download() async {
    final e = extractor.value;
    final uri = Uri.tryParse(url.value);
    if (e == null || uri == null) return;
    await _pausePage();
    await e.openDownload(uri);
  }

  Future<void> _run(bool on) async {
    if (!Platform.isAndroid) return;
    // Android keeps a hidden WebView running the page's scripts, ads and video;
    // pauseTimers stops them for every WebView in the app until resumed.
    final w = web;
    if (w == null) return;
    if (on) {
      await w.resumeTimers();
      if (foreground) await w.resume();
    } else {
      await w.pause();
      await w.pauseTimers();
    }
  }

  Future<void> _pausePage() async {
    // So the page's video doesn't keep playing under a sheet.
    try {
      await web?.evaluateJavascript(source: 'document.querySelectorAll("video,audio").forEach(v => v.pause());');
    } catch (_) {}
  }

  // ------------------------------------------------------------ found media

  Future<void> chooseQuality(CapturedMedia m) async {
    if (!m.isStream || m.variants.length <= 1 || m.kind == DownloadKind.audio) {
      return downloadMedia(m);
    }
    final v = await showOptionSheet<StreamVariant>(
      title: 'Quality',
      options: <SheetOption<StreamVariant>>[
        for (final v in m.variants)
          SheetOption(
            value: v,
            label: '${v.height}p',
            subtitle: _sizeFor(m, v) > 0 ? '~${Formatters.bytes(_sizeFor(m, v))}' : null,
            icon: Icons.high_quality_rounded,
          ),
      ],
    );
    if (v != null) await downloadMedia(m, variant: v);
  }

  Future<void> downloadMedia(CapturedMedia m, {StreamVariant? variant}) async {
    if (m.protected) {
      showSnack('Protected video', "This video is DRM-protected and can't be downloaded.");
      return;
    }
    if (!m.isStream) {
      await DownloadService.to.enqueueDirect(
        url: m.url,
        fileName: '${m.title}.${m.ext}',
        size: m.size,
        pageUrl: m.pageUrl,
        headers: m.headers,
        thumbnailUrl: m.poster,
        subtitles: m.subtitles,
      );
    } else {
      final h = variant?.height ?? m.bestHeight;
      final audio = m.kind == DownloadKind.audio;
      await DownloadService.to.enqueueStream(
        url: m.url,
        title: m.title,
        format: audio
            ? 'ba/b'
            : h > 0
            ? 'bv*[height<=$h]+ba/b[height<=$h]/bv*+ba/b'
            : 'bv*+ba/b',
        kind: m.kind,
        extension: audio ? 'm4a' : 'mp4',
        qualityLabel: !audio && h > 0 ? '${h}p' : '',
        thumbnailUrl: m.poster,
        size: _sizeFor(m, variant),
        pageUrl: m.pageUrl,
        headers: m.headers,
        subtitles: m.subtitles,
      );
    }
    showDownloadStarted(m.title);
  }

  Future<void> preview(CapturedMedia m) async {
    // The player sends these headers with every piece and key of a stream,
    // whatever their host, so a stream gets no cookies.
    final cookies = m.isStream ? '' : await _cookies(m.url);
    await _run(false);
    await Get.toNamed(
      Routes.videoPlayer,
      arguments: VideoPlaylist([
        VideoItem(
          uri: m.url,
          title: m.title,
          httpHeaders: {...m.headers, if (cookies.isNotEmpty) 'Cookie': cookies},
          thumbnailUrl: m.poster.isEmpty ? null : m.poster,
        ),
      ]),
    );
    await _run(true);
  }

  // ------------------------------------------------------------- image menu

  static const _clipboard = MethodChannel('toomu/clipboard');
  // Made on first use: up to 30 restored tabs, most never touched.
  Dio? _imageDioOrNull;
  Dio get _imageDio => _imageDioOrNull ??= Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)),
  );

  /// Long press on a link or picture: Chrome's menu for it (Android;
  /// Windows' WebView2 has its own on right-click).
  Future<void> onLongPress(InAppWebViewHitTestResult hit) async {
    final type = hit.type;
    final onImage =
        type == InAppWebViewHitTestResultType.IMAGE_TYPE || type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
    final onLink =
        type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
        type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
    if (!onImage && !onLink) return;

    PageLink? link;
    if (onLink) {
      String? href;
      try {
        href = (await web?.requestFocusNodeHref())?.url?.toString();
      } catch (_) {}
      if ((href == null || href.isEmpty) && type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE) href = hit.extra;
      if (href != null && href.isNotEmpty) link = PageLink(href: href, text: await _linkText(href));
    }
    PageImage? image;
    if (onImage) {
      // On an image inside a link, `extra` can be the link: ask for the image.
      String? src;
      try {
        src = (await web?.requestImageRef())?.url?.toString();
      } catch (_) {}
      if (src == null || src.isEmpty) src = hit.extra;
      if (src != null && src.isNotEmpty && src != link?.href) image = await _pageImage(src);
    }
    if (link == null && image == null) return;
    final picked = await showPageMenu(
      link: link,
      image: image,
      entries: pageMenuEntries(link: link, image: image, canCopyImage: HostOs.isAndroid, incognito: incognito),
    );
    if (picked is LinkAction) await runLinkAction(link!, picked);
    if (picked is ImageAction) await runImageAction(image!, picked);
  }

  Future<String> _linkText(String href) async {
    try {
      final r = await web
          ?.callAsyncJavaScript(functionBody: linkTextJs, arguments: {'href': href})
          .timeout(const Duration(milliseconds: 600));
      return r?.value is String ? r!.value as String : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> runLinkAction(PageLink link, LinkAction action) async {
    try {
      switch (action) {
        case LinkAction.openNewTab:
          openTab?.call(link.href, background: true);
        case LinkAction.openIncognito:
          openIncognito?.call(link.href);
        case LinkAction.copyAddress:
          await Clipboard.setData(ClipboardData(text: link.href));
          showSnack('Link copied', displayAddress(link.href), duration: const Duration(seconds: 2));
        case LinkAction.copyText:
          await Clipboard.setData(ClipboardData(text: link.text.trim()));
          showSnack('Text copied', link.title, duration: const Duration(seconds: 2));
        case LinkAction.download:
          final ua = capture.userAgent;
          await DownloadService.to.enqueueDirect(
            url: link.href,
            pageUrl: url.value,
            headers: {if (ua.isNotEmpty) 'User-Agent': ua, 'Referer': url.value},
          );
          showDownloadStarted(link.title);
        case LinkAction.share:
          final uri = Uri.tryParse(link.href);
          await SharePlus.instance.share(
            link.isWebLink && uri != null ? ShareParams(uri: uri) : ShareParams(text: link.href),
          );
      }
    } catch (e) {
      showSnack("Couldn't ${action.label.toLowerCase()}", ErrorText.of(e));
    }
  }

  Future<PageImage> _pageImage(String src) async {
    final ua = capture.userAgent;
    final cookies = src.startsWith('http') ? await _cookies(src) : '';
    String alt = '';
    try {
      final r = await web
          ?.callAsyncJavaScript(functionBody: imageAltJs, arguments: {'src': src})
          .timeout(const Duration(milliseconds: 600));
      if (r?.value is String) alt = r!.value as String;
    } catch (_) {}
    return PageImage(
      src: src,
      alt: alt,
      pageUrl: url.value,
      headers: {
        if (ua.isNotEmpty) 'User-Agent': ua,
        if (url.value.isNotEmpty) 'Referer': url.value,
        if (cookies.isNotEmpty) 'Cookie': cookies,
      },
    );
  }

  Future<({Uint8List bytes, String mimeType})> _imageBytes(PageImage image) =>
      loadImageBytes(image, dio: _imageDio, readBlob: _readBlob);

  Future<String?> _readBlob(String src) async {
    final r = await web?.callAsyncJavaScript(functionBody: blobToDataUrlJs, arguments: {'src': src});
    return r?.value is String ? r!.value as String : null;
  }

  /// [image] in a file of its own under the app's cache [folder] (for the
  /// clipboard and sharing, which take files).
  Future<({File file, String mimeType})> _imageFile(PageImage image, String folder) async {
    final got = await _imageBytes(image);
    final dir = await Directory('${(await getTemporaryDirectory()).path}/$folder').create(recursive: true);
    // One file at a time: the previous copy or share is done with.
    for (final old in dir.listSync()) {
      try {
        old.deleteSync(recursive: true);
      } catch (_) {}
    }
    final file = File('${dir.path}/${imageFileName(image, mimeType: got.mimeType)}');
    await file.writeAsBytes(got.bytes, flush: true);
    return (file: file, mimeType: got.mimeType);
  }

  Future<void> runImageAction(PageImage image, ImageAction action) async {
    try {
      switch (action) {
        case ImageAction.open:
          openTab?.call(image.src, background: true);
        case ImageAction.preview:
          await _run(false);
          await Get.to<void>(
            () => ImagePreviewPage(title: image.title, bytes: _imageBytes(image).then((r) => r.bytes)),
            transition: Transition.fadeIn,
          );
          await _run(true);
        case ImageAction.copy:
          final f = await _imageFile(image, 'clipboard');
          final systemShown = await _clipboard.invokeMethod<bool>('copyImage', {
            'path': f.file.path,
            'mimeType': f.mimeType,
            'label': image.title,
          });
          // Android 13+ shows its own "copied" preview.
          if (systemShown != true) showSnack('Image copied', image.title, duration: const Duration(seconds: 2));
        case ImageAction.copyLink:
          await Clipboard.setData(ClipboardData(text: image.src));
          showSnack('Link copied', Uri.tryParse(image.src)?.host ?? '', duration: const Duration(seconds: 2));
        case ImageAction.download:
          if (image.isWebLink) {
            await DownloadService.to.enqueueDirect(
              url: image.src,
              fileName: imageFileName(image),
              pageUrl: url.value,
              headers: {
                for (final e in image.headers.entries)
                  if (e.key != 'Cookie') e.key: e.value,
              },
              thumbnailUrl: image.src,
            );
            showDownloadStarted(image.title);
          } else {
            final got = await _imageBytes(image);
            await DownloadService.to.saveBytes(
              bytes: got.bytes,
              fileName: imageFileName(image, mimeType: got.mimeType),
              pageUrl: url.value,
              mimeType: got.mimeType,
            );
            showSnack('Image saved', image.title, duration: const Duration(seconds: 3));
          }
        case ImageAction.lens:
          openTab?.call(lensUrl(image.src).toString(), background: false);
        case ImageAction.share:
          final f = await _imageFile(image, 'share');
          await SharePlus.instance.share(ShareParams(files: [XFile(f.file.path, mimeType: f.mimeType)]));
      }
    } catch (e) {
      showSnack("Couldn't ${action.label.toLowerCase()}", ErrorText.of(e));
    }
  }

  Future<void> copyLink(CapturedMedia m) async {
    await Clipboard.setData(ClipboardData(text: m.url));
    showSnack('Link copied', m.host, duration: const Duration(seconds: 2));
  }

  static int _sizeFor(CapturedMedia m, StreamVariant? v) {
    final d = m.duration;
    return v != null && d != null && v.bandwidth > 0 ? v.bandwidth ~/ 8 * d.inSeconds : m.size;
  }

  // -------------------------------------------------------- yt-dlp on the page

  Future<void> searchPage() async {
    if (searching.value || !HostOs.hasYtDlp) return;
    searching.value = true;
    searchError.value = null;
    final page = url.value;
    try {
      final cookies = await _cookies(page);
      final info = await YtDlpService.to.pageInfo(
        page,
        DownloadService.headerArgs({..._pageHeaders(), if (cookies.isNotEmpty) 'Cookie': cookies}),
      );
      if (url.value != page) return;
      _searchedUrl = page;
      pageResult.value = info;
    } catch (e) {
      searchError.value = ErrorText.of(e);
    } finally {
      searching.value = false;
    }
  }

  List<MediaFormat> pageFormats(YtInfo info) {
    final list = [...MediaFormat.videoOptions(info), ...MediaFormat.audioOptions(info)];
    return list.isNotEmpty
        ? list
        : const [
            MediaFormat(
              kind: DownloadKind.video,
              label: 'Best',
              extension: 'mp4',
              sizeBytes: 0,
              detail: 'MP4',
              selector: 'bv*+ba/b',
            ),
          ];
  }

  Future<void> downloadPageFormat(YtInfo info, MediaFormat f) async {
    await DownloadService.to.enqueueStream(
      url: _searchedUrl,
      title: info.title,
      format: f.selector,
      kind: f.kind,
      extension: f.extension,
      convert: f.convert,
      qualityLabel: f.kind == DownloadKind.video ? f.label : '',
      thumbnailUrl: info.thumbnail ?? '',
      size: f.sizeBytes,
      pageUrl: _searchedUrl,
      headers: _pageHeaders(),
    );
    showDownloadStarted(info.title);
  }

  Map<String, String> _pageHeaders() => {if (capture.userAgent.isNotEmpty) 'User-Agent': capture.userAgent};

  // ------------------------------------------------------------ link refresh

  void _maybeRefresh(CapturedMedia m) {
    final task = refreshFor;
    final old = task?.url;
    if (task == null || old == null || _refreshed) return;
    if (m.isStream != (task.source == DownloadSource.stream)) return;
    if (!MediaManifest.sameMedia(old, task.totalBytes.value, m.url, m.size)) return;
    _refreshed = true;
    DownloadService.to.replaceLink(task, m.url, m.headers, size: m.size);
    // Before the snackbar: closing the browser would close it instead.
    // Only this tab goes, unless the browser was opened just for it.
    onRefreshed?.call();
    showSnack('Link refreshed', 'The download continues.', duration: const Duration(seconds: 3));
  }

  /// Back navigates inside the site first, then closes the browser.
  /// Back: closes find, goes back a page, or back to the new-tab page this
  /// tab started on. False when there's nothing left (the session then
  /// closes the tab or the browser).
  Future<bool> handleBack() async {
    if (addressFocused.value) {
      addressFocus.unfocus();
      return false;
    }
    if (finding.value) {
      await stopFind();
      return false;
    }
    if (showingNewTab.value) return true;
    if (await web?.canGoBack() ?? false) {
      await web!.goBack();
      return false;
    }
    if (_cameFromNewTab) {
      showNewTabPage();
      return false;
    }
    return true;
  }

  void reload() => web?.reload();
  void goForward() => web?.goForward();

  void _detect(String raw) {
    final uri = Uri.tryParse(raw);
    extractor.value = uri == null ? null : Extractors.find(uri);
  }
}

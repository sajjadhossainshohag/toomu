import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

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
import '../../../services/download_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/ytdlp_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/option_sheet.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../media_capture.dart';
import '../media_sniffer.dart';
import '../views/media_sheet.dart';

/// Snaptube-style in-app browser. Sites load in a real WebView (real
/// cookies and session, like any mobile browser); when the current page is
/// something an extractor supports, the Download button appears.
class BrowserController extends GetxController {
  static const homeUrl = 'https://m.youtube.com/';

  // Opened from a download whose link expired: find the same file again.
  final DownloadTask? refreshFor = Get.arguments is DownloadTask ? Get.arguments as DownloadTask : null;

  late final String initialUrl =
      refreshFor?.pageUrl ?? (Get.arguments is String ? Get.arguments as String : homeUrl);

  final address = TextEditingController();
  final url = ''.obs;
  final title = ''.obs;
  final progress = 0.0.obs;
  final canGoBack = false.obs;
  final canGoForward = false.obs;
  final extractor = Rxn<MediaExtractor>();
  final capture = MediaCapture();

  final webKey = 0.obs;
  String restoreUrl = '';

  final pageResult = Rxn<YtInfo>();
  final searching = false.obs;
  final searchError = RxnString();
  String _searchedUrl = '';
  bool _refreshed = false;

  InAppWebViewController? web;

  final settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    useOnDownloadStart: true, // 1DM-style: catch file downloads
    useOnRenderProcessGone: true,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    supportZoom: false,
    useShouldOverrideUrlLoading: true,
  );

  final userScripts = UnmodifiableListView<UserScript>([
    if (SettingsService.to.captureMedia.value)
      UserScript(
        source: mediaSnifferJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
  ]);

  @override
  void onInit() {
    super.onInit();
    url.value = initialUrl;
    restoreUrl = initialUrl;
    address.text = initialUrl;
    capture.onFound = _maybeRefresh;
    _detect(initialUrl);
  }

  @override
  void onClose() {
    address.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------- WebView hooks

  void onCreated(InAppWebViewController c) {
    web = c;
    c.addJavaScriptHandler(
      handlerName: 'toomuMedia',
      callback: (List<dynamic> args) {
        final m = args.isEmpty ? null : args.first;
        if (m is Map) capture.onReport(Map<String, dynamic>.from(m));
        return null;
      },
    );
  }

  void onLoadStart(WebUri? u) {
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
    if (!_editingAddress) address.text = url.value;
    _detect(url.value);
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

  void onIosProcessGone() => web?.reload();

  void onTitle(String? t) => title.value = t ?? '';

  void onProgress(int p) => progress.value = p / 100;

  /// Opens app links (intent://, market://) outside instead of erroring.
  NavigationActionPolicy onNavigate(NavigationAction action) {
    final scheme = action.request.url?.scheme ?? 'https';
    return scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'data'
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  /// A link the site serves as a file download.
  Future<void> onDownloadStart(DownloadStartRequest request) {
    final ua = request.userAgent ?? capture.userAgent;
    return DirectFileExtractor.confirmAndDownload(
      request.url.toString(),
      fileName: request.suggestedFilename,
      size: request.contentLength,
      pageUrl: url.value,
      headers: {if (ua.isNotEmpty) 'User-Agent': ua, 'Referer': url.value},
    );
  }

  // ------------------------------------------------------------------ actions

  bool _editingAddress = false;

  void onAddressFocus(bool focused) => _editingAddress = focused;

  /// URL → open it; anything else → search (YouTube when on YouTube).
  void submit(String input) {
    final text = input.trim();
    if (text.isEmpty) return;
    _editingAddress = false;
    final looksLikeUrl = !text.contains(' ') && text.contains('.');
    final String target;
    if (looksLikeUrl) {
      target = text.startsWith('http') ? text : 'https://$text';
    } else if (Uri.tryParse(url.value)?.host.contains('youtube.com') ?? false) {
      target = 'https://m.youtube.com/results?search_query=${Uri.encodeQueryComponent(text)}';
    } else {
      target = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}';
    }
    web?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  String? get fabLabel {
    if (extractor.value != null) return 'Download';
    final n = capture.items.length;
    if (n > 0) return '$n found';
    return Platform.isAndroid ? 'Find videos' : null;
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

  Future<void> _pausePage() async {
    // So the page's video doesn't keep playing under a sheet.
    await web?.evaluateJavascript(
        source: 'document.querySelectorAll("video").forEach(v => v.pause());');
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
      );
    }
    showSnack('Download started', m.title, duration: const Duration(seconds: 2));
  }

  Future<void> preview(CapturedMedia m) async {
    final cookies = await DownloadService.webCookies(m.url);
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
    if (searching.value || !Platform.isAndroid) return;
    searching.value = true;
    searchError.value = null;
    final page = url.value;
    try {
      final cookies = await DownloadService.webCookies(page);
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
    showSnack('Download started', info.title, duration: const Duration(seconds: 2));
  }

  Map<String, String> _pageHeaders() => {
    if (capture.userAgent.isNotEmpty) 'User-Agent': capture.userAgent,
  };

  // ------------------------------------------------------------ link refresh

  void _maybeRefresh(CapturedMedia m) {
    final task = refreshFor;
    final old = task?.url;
    if (task == null || old == null || _refreshed) return;
    if (m.isStream != (task.source == DownloadSource.stream)) return;
    if (!MediaManifest.sameMedia(old, task.totalBytes.value, m.url, m.size)) return;
    _refreshed = true;
    DownloadService.to.replaceLink(task, m.url, m.headers, size: m.size);
    // Back first: Get.back() would close the snackbar instead of the page.
    Get.back();
    showSnack('Link refreshed', 'The download continues.', duration: const Duration(seconds: 3));
  }

  /// Back navigates inside the site first, then closes the browser.
  Future<bool> handleBack() async {
    if (await web?.canGoBack() ?? false) {
      await web!.goBack();
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

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../extractors/direct_file_extractor.dart';
import '../../../extractors/extractors.dart';

/// Snaptube-style in-app browser. Sites load in a real WebView (real
/// cookies and session, like any mobile browser); when the current page is
/// something an extractor supports, the Download button appears.
class BrowserController extends GetxController {
  static const homeUrl = 'https://m.youtube.com/';

  late final String initialUrl = (Get.arguments as String?) ?? homeUrl;

  final address = TextEditingController();
  final url = ''.obs;
  final title = ''.obs;
  final progress = 0.0.obs;
  final canGoBack = false.obs;
  final canGoForward = false.obs;
  final extractor = Rxn<MediaExtractor>();

  InAppWebViewController? web;

  final settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    useOnDownloadStart: true, // 1DM-style: catch file downloads
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    supportZoom: false,
    useShouldOverrideUrlLoading: true,
  );

  @override
  void onInit() {
    super.onInit();
    url.value = initialUrl;
    address.text = initialUrl;
    _detect(initialUrl);
  }

  @override
  void onClose() {
    address.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------- WebView hooks

  void onCreated(InAppWebViewController c) => web = c;

  /// YouTube is a single-page app: video changes arrive as history updates,
  /// not page loads, so detection hangs off this callback.
  Future<void> onHistoryChanged(WebUri? u) async {
    if (u == null) return;
    url.value = u.toString();
    if (!_editingAddress) address.text = url.value;
    _detect(url.value);
    canGoBack.value = await web?.canGoBack() ?? false;
    canGoForward.value = await web?.canGoForward() ?? false;
  }

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
  Future<void> onDownloadStart(DownloadStartRequest request) =>
      DirectFileExtractor.confirmAndDownload(
        request.url.toString(),
        fileName: request.suggestedFilename,
        size: request.contentLength,
      );

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

  Future<void> download() async {
    final e = extractor.value;
    final uri = Uri.tryParse(url.value);
    if (e == null || uri == null) return;
    // Pause in-page playback so it doesn't play under the format sheet.
    await web?.evaluateJavascript(
        source: 'document.querySelectorAll("video").forEach(v => v.pause());');
    await e.openDownload(uri);
  }

  void reload() => web?.reload();
  void goForward() => web?.goForward();

  /// Back navigates inside the site first, then closes the browser.
  Future<bool> handleBack() async {
    if (await web?.canGoBack() ?? false) {
      await web!.goBack();
      return false;
    }
    return true;
  }

  void _detect(String raw) {
    final uri = Uri.tryParse(raw);
    extractor.value = uri == null ? null : Extractors.find(uri);
  }
}

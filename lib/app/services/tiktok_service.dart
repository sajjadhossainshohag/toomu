import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/tiktok_item.dart';

/// TikTok links → downloads (no watermark; yt-dlp does the download). The
/// video's page is read first for its caption, author and cover.
abstract class TiktokService {
  /// One browser identity for the WebView, the app's requests and yt-dlp
  /// (TikTok's firewall pass is tied to it).
  static const agent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

  /// TikTok links in [text] (tiktok.com/@x/video/1, vm./vt. short links).
  static String? linkIn(String text) {
    final m = RegExp(
      r'https?://(?:[a-z]+\.)?tiktok\.com/[^\s।]+',
      caseSensitive: false,
    ).firstMatch(text);
    return m?.group(0)?.replaceFirst(RegExp(r'[)\].,!?]+$'), '');
  }

  /// The video behind [url] (short links followed). Its caption, author
  /// and cover come from the video's page. TikTok sometimes answers with a
  /// JavaScript check (its "SlardarWAF" firewall) instead of the page; then
  /// a bare entry for the link — yt-dlp gets past the check when it
  /// downloads. Null only when [url] clearly isn't a TikTok video.
  static Future<TiktokItem?> itemFromUrl(String url) async {
    final sw = Stopwatch()..start();
    var finalUrl = url;
    var blocked = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    client.userAgent = agent;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
      final pass = await _cookieHeader();
      if (pass.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, pass);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.redirects.isNotEmpty) {
        finalUrl = Uri.parse(
          url,
        ).resolveUri(res.redirects.last.location).toString();
      }
      final html = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final item = parseVideoPage(html);
      blocked = isFirewallPage(html);
      debugPrint(
        '[TikTok] link → ${res.statusCode} ${_short(finalUrl)}: '
        '${item != null
            ? 'details read'
            : blocked
            ? "TikTok's bot check"
            : 'no details in the page'} '
        '(${sw.elapsedMilliseconds} ms)',
      );
      if (item != null) return item;
    } catch (e) {
      debugPrint('[TikTok] page failed: $e');
    } finally {
      client.close(force: true);
    }
    // yt-dlp gets past TikTok's check by itself (confirmed on a phone):
    // download straight from the link, no waiting.
    if (blocked) debugPrint("[TikTok] bot check: downloading from the link (yt-dlp reads the page)");
    return bareItem(finalUrl, original: url);
  }

  /// TikTok's firewall check page instead of the video page.
  @visibleForTesting
  static bool isFirewallPage(String html) =>
      html.contains('_wafchallengeid') ||
      (html.contains('SlardarWAF') && html.length < 20000);

  static Future<List<Cookie>> _cookies() async {
    try {
      return await CookieManager.instance().getCookies(
        url: WebUri('https://www.tiktok.com/'),
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<String> _cookieHeader() async =>
      (await _cookies()).map((c) => '${c.name}=${c.value}').join('; ');

  /// yt-dlp options for TikTok: the WebView's cookies (TikTok's firewall
  /// pass) with the same browser identity they were issued to.
  static Future<List<String>> ytDlpArgs() async {
    final cookies = await _cookies();
    final args = <String>['--user-agent', agent];
    if (cookies.isEmpty) return args;
    final at =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
        1000;
    final out = StringBuffer('# Netscape HTTP Cookie File\n');
    for (final c in cookies) {
      final value = '${c.value ?? ''}';
      if (c.name.isEmpty || value.contains(RegExp(r'[\t\r\n]'))) continue;
      out.writeln(
        ['.tiktok.com', 'TRUE', '/', 'TRUE', '$at', c.name, value].join('\t'),
      );
    }
    final file = File(
      '${(await getApplicationSupportDirectory()).path}/tiktok_cookies.txt',
    );
    await file.writeAsString(out.toString(), flush: true);
    return [...args, '--cookies', file.path];
  }

  /// An entry with only what the link itself says.
  @visibleForTesting
  static TiktokItem? bareItem(String finalUrl, {String? original}) {
    final m = RegExp(r'/(?:video|v|photo)/(\d{8,})').firstMatch(finalUrl);
    final author = RegExp(r'/@([^/?#]+)').firstMatch(finalUrl)?.group(1);
    final short =
        original != null &&
        RegExp(
          r'//(vm|vt)\.tiktok\.com/',
          caseSensitive: false,
        ).hasMatch(original);
    if (m == null && !short) return null;
    return TiktokItem(
      id: m?.group(1) ?? '${DateTime.now().millisecondsSinceEpoch}',
      authorId: author ?? 'tiktok',
      pageUrl: m != null ? _clean(finalUrl) : original,
    );
  }

  /// Without tracking parameters (yt-dlp doesn't need them).
  static String _clean(String url) => url.split('?').first;

  static String _short(String url) =>
      url.length > 80 ? '${url.substring(0, 80)}…' : url;

  @visibleForTesting
  static TiktokItem? parseVideoPage(String html) {
    final m = RegExp(
      r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (m == null) return null;
    try {
      final data = jsonDecode(m[1]!) as Map<String, dynamic>;
      final item =
          (((data['__DEFAULT_SCOPE__'] as Map?)?['webapp.video-detail']
                  as Map?)?['itemInfo']
              as Map?)?['itemStruct'];
      return item is Map<String, dynamic> ? TiktokItem.fromJson(item) : null;
    } catch (_) {
      return null;
    }
  }
}

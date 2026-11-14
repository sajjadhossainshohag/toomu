import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// The user's YouTube sign-in, used only for videos YouTube won't show
/// without one (age-restricted). Everything else stays anonymous.
///
/// The session is captured from the sign-in WebView into a private cookie
/// file for yt-dlp (`--cookies`; yt-dlp writes refreshed cookies back).
/// The WebViews then forget it: YouTube's own pages rotate a session's
/// cookies, which would make the saved copy stop working.
class YoutubeAccountService extends GetxService {
  static YoutubeAccountService get to => Get.find();

  final signedIn = false.obs;

  /// The saved session stopped working (signed out elsewhere, expired).
  final expired = false.obs;

  String _cookieFile = '';

  Future<YoutubeAccountService> init() async {
    final dir = await getApplicationSupportDirectory(); // private, not cache
    _cookieFile = '${dir.path}/youtube_account.txt';
    signedIn.value = File(_cookieFile).existsSync();
    return this;
  }

  /// The saved session's cookies (name → value); empty when signed out.
  /// Read fresh each time: yt-dlp writes refreshed ones back to the file.
  Future<Map<String, String>> cookies() async {
    if (!signedIn.value) return const {};
    try {
      return parseNetscapeCookies(await File(_cookieFile).readAsString());
    } catch (_) {
      return const {};
    }
  }

  @visibleForTesting
  static Map<String, String> parseNetscapeCookies(String text) {
    final out = <String, String>{};
    for (var line in text.split('\n')) {
      // yt-dlp marks HttpOnly cookies "#HttpOnly_<domain>".
      if (line.startsWith('#HttpOnly_')) line = line.substring(10);
      if (line.isEmpty || line.startsWith('#')) continue;
      final f = line.split('\t');
      if (f.length < 7 || !f[0].endsWith('youtube.com')) continue;
      out[f[5]] = f[6].trimRight();
    }
    return out;
  }

  /// yt-dlp options that use the account (none when signed out).
  List<String> get ytDlpArgs => signedIn.value ? ['--cookies', _cookieFile] : const [];

  /// Cookies yt-dlp needs to act as the signed-in user.
  static const _sessionCookies = {'SAPISID', '__Secure-3PAPISID'};

  /// Saves the WebView's YouTube session. False while not signed in yet.
  Future<bool> captureSession() async {
    final cookies = await CookieManager.instance().getCookies(url: WebUri('https://www.youtube.com/'));
    if (!cookies.any((c) => _sessionCookies.contains(c.name))) return false;
    final file = File(_cookieFile);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      netscapeCookies(
        [for (final c in cookies) (c.name, '${c.value ?? ''}')],
        expires: DateTime.now().add(const Duration(days: 400)),
      ),
      flush: true,
    );
    signedIn.value = true;
    expired.value = false;
    debugPrint('[Account] signed in (${cookies.length} cookies saved)');
    await forgetWebSession();
    return true;
  }

  Future<void> signOut() async {
    try {
      await File(_cookieFile).delete();
    } catch (_) {}
    signedIn.value = false;
    await forgetWebSession();
    debugPrint('[Account] signed out');
  }

  /// yt-dlp said the saved session no longer works.
  Future<void> markExpired() async {
    await signOut();
    expired.value = true;
  }

  /// Removes YouTube / Google sign-in cookies from the app's WebViews.
  static Future<void> forgetWebSession() async {
    final manager = CookieManager.instance();
    const sites = <(String, List<String?>)>[
      ('https://www.youtube.com/', ['.youtube.com', null]),
      ('https://m.youtube.com/', ['.youtube.com', null]),
      ('https://accounts.google.com/', ['.google.com', 'accounts.google.com', null]),
      ('https://www.google.com/', ['.google.com', null]),
    ];
    for (final (url, domains) in sites) {
      for (final domain in domains) {
        try {
          await manager.deleteCookies(url: WebUri(url), domain: domain);
        } catch (_) {}
      }
    }
  }

  /// [cookies] as a Netscape cookie file (what yt-dlp's `--cookies` reads)
  /// for youtube.com. Android's WebView doesn't report expiry dates, so all
  /// get [expires]; yt-dlp keeps them fresh from YouTube's answers.
  @visibleForTesting
  static String netscapeCookies(Iterable<(String, String)> cookies, {required DateTime expires}) {
    final at = expires.millisecondsSinceEpoch ~/ 1000;
    final out = StringBuffer('# Netscape HTTP Cookie File\n# Toomu: YouTube sign-in for yt-dlp. Private.\n\n');
    final bad = RegExp(r'[\t\r\n]');
    for (final (name, value) in cookies) {
      if (name.isEmpty || bad.hasMatch(name) || bad.hasMatch(value)) continue;
      // "__Host-" cookies belong to one host only.
      final host = name.startsWith('__Host-');
      out.writeln([host ? 'www.youtube.com' : '.youtube.com', host ? 'FALSE' : 'TRUE', '/', 'TRUE', '$at', name, value]
          .join('\t'));
    }
    return out.toString();
  }
}

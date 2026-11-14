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

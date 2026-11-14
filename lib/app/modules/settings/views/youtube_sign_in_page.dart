import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/youtube_account_service.dart';
import '../../../widgets/app_snackbar.dart';

/// Google's own sign-in page for YouTube, inside the app. When the user is
/// signed in, the session is saved for age-restricted videos and the page
/// closes with `true`.
class YoutubeSignInPage extends StatefulWidget {
  const YoutubeSignInPage({super.key});

  /// Opens the page; true once signed in.
  static Future<bool> open() async => await Get.to<bool>(() => const YoutubeSignInPage()) ?? false;

  /// Google's sign-in for YouTube, ending on a plain YouTube page (no
  /// YouTube scripts run that would rotate the fresh session's cookies).
  static const _start = 'https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true'
      '&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop'
      '%26hl%3Den%26next%3D%252Frobots.txt';

  /// A regular mobile Chrome identity. Google refuses sign-in in apps'
  /// WebViews it recognises (the "; wv" marker in the user agent, the
  /// X-Requested-With header — removed in the settings below).
  @visibleForTesting
  static String chromeAgent(String webViewAgent) {
    final version = RegExp(r'Chrome/(\d+)').firstMatch(webViewAgent)?.group(1) ?? '131';
    return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/$version.0.0.0 Mobile Safari/537.36';
  }

  @override
  State<YoutubeSignInPage> createState() => _YoutubeSignInPageState();
}

class _YoutubeSignInPageState extends State<YoutubeSignInPage> {
  String? _agent;
  double _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Start from a clean slate (no half-finished or old web session).
    await YoutubeAccountService.forgetWebSession();
    String agent;
    try {
      agent = YoutubeSignInPage.chromeAgent(await InAppWebViewController.getDefaultUserAgent());
    } catch (_) {
      agent = YoutubeSignInPage.chromeAgent('');
    }
    if (mounted) setState(() => _agent = agent);
  }

  Future<void> _check(WebUri? url) async {
    if (_done || url == null || !url.host.endsWith('youtube.com')) return;
    final ok = await YoutubeAccountService.to.captureSession();
    if (!ok || _done || !mounted) return;
    _done = true;
    Get.back(result: true);
    showSnack('Signed in to YouTube', 'Home now shows your recommendations.', duration: const Duration(seconds: 3));
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final agent = _agent;

    return Scaffold(
      backgroundColor: ColorConstants.surfaceOn(dark),
      appBar: AppBar(
        backgroundColor: ColorConstants.surfaceOn(dark),
        foregroundColor: ink,
        elevation: 0,
        title: Text('Sign in to YouTube', style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress > 0 && _progress < 1
              ? LinearProgressIndicator(value: _progress, minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(16 * scale, 4 * scale, 16 * scale, 10 * scale),
            child: Text(
              'Shows your YouTube recommendations and subscriptions on Home, and unlocks '
              'age-restricted videos. Kept on this phone; a spare Google account is safest.',
              style: TextStyle(fontSize: 12.5 * scale, color: ink.withValues(alpha: 0.65)),
            ),
          ),
          Expanded(
            child: agent == null
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(YoutubeSignInPage._start)),
                    initialSettings: InAppWebViewSettings(
                      userAgent: agent,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      // Don't announce the app (X-Requested-With) to Google.
                      requestedWithHeaderOriginAllowList: <String>{},
                      supportMultipleWindows: false,
                    ),
                    onProgressChanged: (_, p) => setState(() => _progress = p / 100),
                    onLoadStop: (_, url) => _check(url),
                    onUpdateVisitedHistory: (_, url, _) => _check(url),
                  ),
          ),
        ],
      ),
    );
  }
}

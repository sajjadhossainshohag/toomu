import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/tiktok_account_service.dart';
import '../../../services/tiktok_service.dart';
import '../../../widgets/app_snackbar.dart';

/// TikTok's own login page, inside the app. Signed in = TikTok's session
/// cookie is there; the page then closes with `true`.
class TiktokSignInPage extends StatefulWidget {
  const TiktokSignInPage({super.key});

  /// Opens the page; true once signed in.
  static Future<bool> open() async =>
      await Get.to<bool>(() => const TiktokSignInPage()) ?? false;

  /// After login TikTok goes to For You.
  static const start =
      'https://www.tiktok.com/login?redirect_url=https%3A%2F%2Fwww.tiktok.com%2Fforyou';

  @visibleForTesting
  static InAppWebViewSettings settings() => InAppWebViewSettings(
    // The feed pages' identity: TikTok ties the session to it.
    userAgent: TiktokService.agent,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    thirdPartyCookiesEnabled: true,
    // Laid out at the phone's own width (TikTok's login fits it, checked in
    // Chrome at 392 px). A wide viewport with overview mode made Android
    // lay it out ~980 px wide and zoom out to fit: tiny and broken.
    useWideViewPort: false,
    loadWithOverviewMode: false,
    supportZoom: false,
    builtInZoomControls: false,
    supportMultipleWindows: false,
  );

  @override
  State<TiktokSignInPage> createState() => _TiktokSignInPageState();
}

class _TiktokSignInPageState extends State<TiktokSignInPage> {
  double _progress = 0;
  bool _done = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Some logins finish without a page load (TikTok's own scripts).
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_done) return;
    final ok = await TiktokAccountService.to.refresh();
    if (!ok || _done || !mounted) return;
    _done = true;
    Get.back(result: true);
    showSnack(
      'Signed in to TikTok',
      'For You now follows your account; Following shows who you follow.',
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    return Scaffold(
      backgroundColor: ColorConstants.surfaceOn(dark),
      appBar: AppBar(
        backgroundColor: ColorConstants.surfaceOn(dark),
        foregroundColor: ink,
        elevation: 0,
        title: Text(
          'Sign in to TikTok',
          style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.w700),
        ),
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
            padding: EdgeInsets.fromLTRB(
              16 * scale,
              4 * scale,
              16 * scale,
              10 * scale,
            ),
            child: Text(
              'Use phone, email or username (Google sign-in is refused inside apps). '
              'Your For You and Following then come from your account. Kept on this phone.',
              style: TextStyle(
                fontSize: 12.5 * scale,
                color: ink.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(TiktokSignInPage.start),
              ),
              initialSettings: TiktokSignInPage.settings(),
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onLoadStop: (_, _) => _check(),
              onUpdateVisitedHistory: (_, _, _) => _check(),
            ),
          ),
        ],
      ),
    );
  }
}

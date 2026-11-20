import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/host_os.dart';

/// Incognito tabs' own cookies and site data, kept apart from normal tabs and deleted when the last incognito tab
/// closes (or the browser does). One session at a time: every incognito tab open together shares it, like Chrome.
///
/// - Android: a WebView profile per session (`toomu/incognito` → IncognitoBridge.kt), set on each incognito tab's
///   WebView before its first page. Needs a WebView with profiles (Android System WebView 125+ or so): see
///   [supported].
/// - Windows: WebView2's InPrivate mode (the `incognito` setting); WebView2 deletes its data when the last
///   InPrivate WebView closes.
abstract final class Incognito {
  static const _channel = MethodChannel('toomu/incognito');

  static String? _session;
  static bool? _supported;

  /// The current session's name (Android: its WebView profile), started by the first incognito tab.
  static String get session => _session ??= 'incognito-${DateTime.now().microsecondsSinceEpoch}';

  /// Called with the session that ended (tests only).
  @visibleForTesting
  static void Function(String session)? onEnd;

  /// Incognito tabs can keep their data apart on this device.
  static Future<bool> supported() async {
    if (HostOs.isWindows) return true;
    if (!HostOs.isAndroid) return false;
    try {
      return _supported ??= await _channel.invokeMethod<bool>('supported') ?? false;
    } catch (e) {
      debugPrint('[Browser] incognito check failed: $e');
      return false;
    }
  }

  /// Android: puts tab [web]'s WebView in this session's profile; false if it couldn't (the tab must not load a
  /// page then: it would use normal tabs' cookies). Windows: the setting already did.
  static Future<bool> attach(InAppWebViewController web) async {
    if (!HostOs.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('use', {'viewId': web.getViewId(), 'profile': session}) ?? false;
    } catch (e) {
      debugPrint('[Browser] incognito profile not set: $e');
      return false;
    }
  }

  /// The session's cookies for [url] (`a=1; b=2`), for downloads from an incognito tab ([web]: the tab's WebView).
  static Future<String> cookies(String url, InAppWebViewController? web) async {
    try {
      if (HostOs.isAndroid) {
        return await _channel.invokeMethod<String>('cookies', {'profile': session, 'url': url}) ?? '';
      }
      if (web == null) return '';
      final list = await CookieManager.instance().getCookies(url: WebUri(url), webViewController: web);
      return list.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  /// The last incognito tab closed: its cookies and site data are deleted; the next incognito tab starts a new
  /// session.
  static void end() {
    final s = _session;
    if (s == null) return;
    _session = null;
    onEnd?.call(s);
    if (HostOs.isAndroid) {
      unawaited(
        _channel.invokeMethod<void>('end', {'profile': s}).catchError((Object e) {
          debugPrint('[Browser] incognito data not deleted: $e');
        }),
      );
    }
  }
}

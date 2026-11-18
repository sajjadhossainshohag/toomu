import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// The TikTok account signed in on TikTok's own login page (in the app).
class TiktokUser {
  const TiktokUser({required this.id, this.name = '', this.avatar});

  /// "@name" without the @.
  final String id;
  final String name;
  final String? avatar;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'avatar': avatar};

  static TiktokUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    return TiktokUser(id: id, name: (j['name'] as String?) ?? '', avatar: j['avatar'] as String?);
  }
}

/// TikTok sign-in: the session lives in the app's WebView cookies, which
/// the TikTok tab's pages (For You, Following) and yt-dlp's TikTok
/// downloads all use, so once signed in For You follows the account and
/// Following shows the accounts it follows.
class TiktokAccountService extends GetxService {
  static TiktokAccountService get to => Get.find();

  static const _kUser = 'tiktok_user';
  static const _site = 'https://www.tiktok.com/';

  /// Cookies TikTok sets only for a signed-in session.
  static const _sessionCookies = {'sessionid', 'sessionid_ss', 'sid_tt'};

  final signedIn = false.obs;
  final user = Rxn<TiktokUser>();

  TiktokAccountService init() {
    try {
      user.value = TiktokUser.fromJson(GetStorage().read<Object>(_kUser));
    } catch (_) {}
    signedIn.value = user.value != null;
    unawaited(refresh());
    return this;
  }

  @visibleForTesting
  static bool hasSession(Iterable<String> cookieNames) => cookieNames.any(_sessionCookies.contains);

  /// Reads the WebView's cookies: signed in or not (signed out elsewhere,
  /// session expired). True when signed in.
  Future<bool> refresh() async {
    List<Cookie> cookies;
    try {
      cookies = await CookieManager.instance().getCookies(url: WebUri(_site));
    } catch (_) {
      return signedIn.value;
    }
    final on = hasSession(cookies.map((c) => c.name));
    if (signedIn.value != on) debugPrint('[TikTok] account: ${on ? 'signed in' : 'signed out'}');
    signedIn.value = on;
    if (!on) _saveUser(null);
    return on;
  }

  /// Who is signed in, from a TikTok page's data (see TiktokFeed.userFrom).
  void noteUser(TiktokUser? u) {
    if (u == null || !signedIn.value) return;
    if (u.id == user.value?.id && u.avatar == user.value?.avatar) return;
    _saveUser(u);
  }

  void _saveUser(TiktokUser? u) {
    user.value = u;
    try {
      u == null ? GetStorage().remove(_kUser) : GetStorage().write(_kUser, u.toJson());
    } catch (_) {}
  }

  /// Removes TikTok's cookies from the app (the feeds start over as a visitor).
  Future<void> signOut() async {
    final manager = CookieManager.instance();
    for (final domain in <String?>['.tiktok.com', 'www.tiktok.com', null]) {
      try {
        await manager.deleteCookies(url: WebUri(_site), domain: domain);
      } catch (_) {}
    }
    signedIn.value = false;
    _saveUser(null);
    debugPrint('[TikTok] account: signed out');
  }
}

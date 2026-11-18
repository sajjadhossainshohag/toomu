import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'tiktok_controller.dart';

enum TiktokFeedKind { following, forYou }

/// Which of the TikTok tab's feeds is picked at the top (TikTok's
/// "Following | For You"). Following needs an account: signed out, it
/// shows a sign-in prompt and its feed doesn't load.
class TiktokFeeds extends GetxController {
  TiktokFeeds({required this.signedIn});

  static const forYouTag = 'foryou';
  static const followingTag = 'following';

  final RxBool signedIn;
  final feed = TiktokFeedKind.forYou.obs;

  /// Each feed's controller plays only while its flag is on.
  final forYouShown = true.obs;
  final followingShown = false.obs;

  final _workers = <Worker>[];

  @override
  void onInit() {
    super.onInit();
    _workers.add(everAll([feed, signedIn], (_) => _sync()));
    _sync();
  }

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    super.onClose();
  }

  void _sync() {
    forYouShown.value = feed.value == TiktokFeedKind.forYou;
    followingShown.value =
        feed.value == TiktokFeedKind.following && signedIn.value;
  }

  void pick(TiktokFeedKind kind) => feed.value = kind;

  /// Two taps this close on the same feed's name: a double tap.
  static const doubleTap = Duration(milliseconds: 350);

  DateTime? _lastTap;
  TiktokFeedKind? _lastKind;

  /// A tap on "Following" / "For You": switches at once; a second tap
  /// right after (a double tap) refreshes that feed, like TikTok.
  void tap(TiktokFeedKind kind, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastTap;
    final again =
        last != null && _lastKind == kind && at.difference(last) <= doubleTap;
    _lastTap = again ? null : at;
    _lastKind = kind;
    pick(kind);
    if (again) refreshFeed(kind);
  }

  /// Starts [kind]'s feed over with fresh videos (pull to refresh, double tap).
  void refreshFeed(TiktokFeedKind kind) {
    if (kind == TiktokFeedKind.following && !signedIn.value) return;
    final tag = kind == TiktokFeedKind.following ? followingTag : forYouTag;
    if (!Get.isRegistered<TiktokController>(tag: tag)) return;
    debugPrint('[TikTok] refreshing ${kind.name}');
    Get.find<TiktokController>(tag: tag).reset();
  }
}

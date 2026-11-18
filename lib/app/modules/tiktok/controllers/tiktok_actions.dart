import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../data/models/tiktok_item.dart';
import '../../../data/providers/tiktok/tiktok_video_page.dart';

/// Likes sent to TikTok: the heart turns red at once, TikTok's own like
/// button is pressed on the video's page, and TikTok's answer decides. If
/// TikTok refuses (or doesn't answer), the heart goes back.
class TiktokActions extends GetxController {
  TiktokActions({
    required this.page,
    required this.signedIn,
    required this.signIn,
    this.onProblem,
  });

  final TiktokVideoPage page;
  final RxBool signedIn;

  /// Opens TikTok's sign-in; true once signed in.
  final Future<bool> Function() signIn;

  /// Tells the user something didn't work.
  final void Function(String title, String message)? onProblem;

  /// TikTok has this long to answer a like.
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 45);

  final _liked = <String, bool>{}.obs;
  final _likes = <String, int>{}.obs;
  final _busy = <String>{};

  bool isLiked(TiktokItem item) => _liked[item.id] ?? item.liked;
  int likesOf(TiktokItem item) => _likes[item.id] ?? item.likes;

  @override
  void onClose() {
    unawaited(page.close());
    super.onClose();
  }

  /// A double tap on the video: likes it (never unlikes, like TikTok).
  Future<void> doubleTapLike(TiktokItem item) async {
    if (signedIn.value && isLiked(item)) return;
    await toggleLike(item);
  }

  /// The heart: like, or unlike if liked.
  Future<void> toggleLike(TiktokItem item) async {
    if (!signedIn.value && !await signIn()) return;
    if (!_busy.add(item.id)) return;
    final was = isLiked(item);
    final count = likesOf(item);
    final want = !was;
    _liked[item.id] = want;
    _likes[item.id] = count + (want ? 1 : -1);
    try {
      if (!await _send(item, want)) throw StateError('TikTok refused');
      debugPrint('[TikTok] ${want ? 'liked' : 'unliked'} ${item.id}');
    } catch (e) {
      debugPrint('[TikTok] like of ${item.id} failed: $e');
      _liked[item.id] = was;
      _likes[item.id] = count;
      onProblem?.call(
        want ? "Couldn't like on TikTok" : "Couldn't remove the like",
        'TikTok didn\'t take it. Check the connection and that you\'re signed in.',
      );
    } finally {
      _busy.remove(item.id);
    }
  }

  /// Presses TikTok's like button until TikTok has it as [want] (the
  /// button toggles, and TikTok may have known the video as liked already).
  Future<bool> _send(TiktokItem item, bool want) async {
    await page.open(item.webUrl);
    for (var press = 0; press < 2; press++) {
      final answer = page.events
          .firstWhere((e) => e.kind == 'like' && e.param('aweme_id') == item.id)
          .timeout(timeout);
      await page.run(WebTiktokVideoPage.call('__toomuLike'));
      final e = await answer;
      if (!e.ok) return false;
      if ((e.param('type') == '1') == want) return true;
    }
    return false;
  }
}

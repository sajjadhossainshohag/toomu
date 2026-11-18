import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../data/models/tiktok_comment.dart';
import '../../../data/models/tiktok_item.dart';
import '../../../data/providers/tiktok/tiktok_video_page.dart';

/// One video's comments sheet: TikTok's video page opens its comments and
/// Toomu shows them in TikTok's design; replies open under each comment;
/// comment likes go to TikTok like the video's (red at once, back if
/// TikTok refuses).
class TiktokCommentsController extends GetxController {
  TiktokCommentsController({
    required this.item,
    required this.page,
    required this.signedIn,
    this.onProblem,
  });

  final TiktokItem item;
  final TiktokVideoPage page;
  final RxBool signedIn;
  final void Function(String title, String message)? onProblem;

  /// Without comments by then, the sheet says so.
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 45);

  late final total = item.comments.obs;
  final comments = <TiktokComment>[].obs;
  final loading = false.obs;
  final error = RxnString();
  final hasMore = false.obs;
  final loadingMore = false.obs;

  /// Replies by comment id, whether more are left, and the ones open.
  final replies = <String, List<TiktokComment>>{}.obs;
  final moreReplies = <String, bool>{}.obs;
  final loadingReplies = <String>{}.obs;
  final open = <String>{}.obs;

  final _ids = <String>{};
  StreamSubscription<TiktokPageEvent>? _sub;
  Timer? _timer, _moreTimer;
  final _replyTimers = <String, Timer>{};
  final _busy = <String>{};
  Worker? _account;

  @override
  void onInit() {
    super.onInit();
    _sub = page.events.listen(_on);
    _account = ever(signedIn, (bool on) {
      if (on && comments.isEmpty) unawaited(load());
    });
    if (signedIn.value) unawaited(load());
  }

  @override
  void onClose() {
    _sub?.cancel();
    _account?.dispose();
    _timer?.cancel();
    _moreTimer?.cancel();
    for (final t in _replyTimers.values) {
      t.cancel();
    }
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (!loading.value) return;
      loading.value = false;
      error.value = "TikTok didn't send the comments. Try again.";
    });
    await page.open(item.webUrl);
    await page.run(WebTiktokVideoPage.call('__toomuOpenComments'));
  }

  void _on(TiktokPageEvent e) {
    if (e.kind == 'comments' && e.param('aweme_id') == item.id) {
      final answer = TiktokCommentPage.parse(e.text);
      loadingMore.value = false;
      if (answer == null) return; // TikTok's empty answer for visitors
      _timer?.cancel();
      loading.value = false;
      error.value = null;
      comments.addAll(answer.comments.where((c) => _ids.add(c.id)));
      hasMore.value = answer.hasMore;
      if (answer.total > 0) total.value = answer.total;
    } else if (e.kind == 'replies') {
      final id = e.param('comment_id') ?? e.param('cid');
      final answer = TiktokCommentPage.parse(e.text);
      if (id == null || answer == null) return;
      _replyTimers.remove(id)?.cancel();
      loadingReplies.remove(id);
      final have = replies[id] ?? const <TiktokComment>[];
      final known = {for (final r in have) r.id};
      replies[id] = [...have, ...answer.comments.where((r) => known.add(r.id))];
      moreReplies[id] = answer.hasMore;
    }
  }

  /// Near the end of the list: TikTok's next comments.
  void more() {
    if (!hasMore.value || loadingMore.value || comments.isEmpty) return;
    loadingMore.value = true;
    _moreTimer?.cancel();
    _moreTimer = Timer(
      const Duration(seconds: 15),
      () => loadingMore.value = false,
    );
    unawaited(
      page.run(
        WebTiktokVideoPage.call('__toomuMoreComments', comments.last.text),
      ),
    );
  }

  /// "View N replies" / "Hide".
  void toggleReplies(TiktokComment c) {
    if (open.contains(c.id)) {
      open.remove(c.id);
      return;
    }
    open.add(c.id);
    if ((replies[c.id] ?? const []).isEmpty) loadReplies(c);
  }

  /// The comment's (next) replies from TikTok ("View more").
  void loadReplies(TiktokComment c) {
    if (!loadingReplies.add(c.id)) return;
    _replyTimers[c.id]?.cancel();
    _replyTimers[c.id] = Timer(const Duration(seconds: 20), () {
      if (loadingReplies.remove(c.id)) {
        onProblem?.call(
          "Couldn't load the replies",
          'TikTok didn\'t send them.',
        );
      }
    });
    unawaited(page.run(WebTiktokVideoPage.call('__toomuReplies', c.text)));
  }

  /// The heart of a comment (or reply under [parent]).
  Future<void> toggleLike(TiktokComment c, {String? parent}) async {
    if (!_busy.add(c.id)) return;
    final want = !c.liked;
    final changed = c.copyWith(liked: want, likes: c.likes + (want ? 1 : -1));
    _replace(c.id, changed, parent);
    try {
      var done = false;
      for (var press = 0; press < 2 && !done; press++) {
        final answer = page.events
            .firstWhere(
              (e) =>
                  e.kind == 'commentLike' &&
                  (e.param('cid') ?? e.param('comment_id')) == c.id,
            )
            .timeout(timeout);
        await page.run(WebTiktokVideoPage.call('__toomuLikeComment', c.text));
        final e = await answer;
        if (!e.ok) break;
        done = ((e.param('digg_type') ?? e.param('type')) == '1') == want;
      }
      if (!done) throw StateError('TikTok refused');
    } catch (e) {
      debugPrint('[TikTok] comment like ${c.id} failed: $e');
      _replace(c.id, c, parent);
      onProblem?.call("Couldn't like the comment", "TikTok didn't take it.");
    } finally {
      _busy.remove(c.id);
    }
  }

  void _replace(String id, TiktokComment to, String? parent) {
    if (parent == null) {
      final i = comments.indexWhere((x) => x.id == id);
      if (i >= 0) comments[i] = to;
      return;
    }
    final list = replies[parent];
    if (list == null) return;
    replies[parent] = [for (final r in list) r.id == id ? to : r];
  }
}

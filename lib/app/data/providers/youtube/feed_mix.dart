import 'dart:async';
import 'dart:math';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../youtube_provider.dart';
import 'account_feed.dart';

/// What the signed-out home feed is made of. YouTube has no public
/// "recommended" list without an account, so the feed is a mix of several
/// searches, picked at random each time so it doesn't show the same few
/// kinds of videos on every launch.
abstract class FeedMix {
  /// How many searches one "For you" page mixes.
  static const topicsPerFeed = 4;

  /// Topics for "For you" besides the category tabs' own searches.
  static const extraTopics = <String>[
    'cooking recipes',
    'street food',
    'travel vlog',
    'nature documentary',
    'science explained',
    'space and astronomy',
    'tech review',
    'smartphone review',
    'diy projects',
    'home workout',
    'car review',
    'movie trailers',
    'animated short film',
    'funny animals',
    'history documentary',
    'photography tips',
    'guitar lesson',
    'life hacks',
    'football skills',
    'unboxing',
    'relaxing music',
    'lofi hip hop',
    'dance performance',
    'magic tricks',
    'drawing and painting',
    'motivational speech',
    'coding tutorial',
    'fishing',
    'gardening tips',
    'board games',
  ];

  /// [count] different searches for one "For you" page: up to half from
  /// the user's recent [history] (what YouTube's own "For you" leans on),
  /// the rest at random from [pool]. Topics in [avoid] (the last page's)
  /// are only used when nothing else is left.
  static List<String> pickTopics({
    required Iterable<String> pool,
    required Random random,
    Iterable<String> history = const [],
    Iterable<String> avoid = const [],
    int count = topicsPerFeed,
  }) {
    final avoided = {for (final t in avoid) _key(t)};
    final picked = <String>[];
    final taken = <String>{};

    void takeFrom(Iterable<String> candidates, int want) {
      final list = <String>[
        for (final c in candidates)
          if (c.trim().isNotEmpty && !taken.contains(_key(c))) c.trim(),
      ]..shuffle(random);
      // Fresh topics first, the ones shown last time only if still short.
      final fresh = list.where((c) => !avoided.contains(_key(c)));
      final shownLastTime = list.where((c) => avoided.contains(_key(c)));
      for (final c in [...fresh, ...shownLastTime]) {
        if (want <= 0) break;
        if (taken.add(_key(c))) {
          picked.add(c);
          want--;
        }
      }
    }

    takeFrom(history.take(6), count ~/ 2);
    takeFrom(pool, count - picked.length);
    picked.shuffle(random); // the user's searches aren't always on top
    return picked;
  }

  static String _key(String topic) => topic.trim().toLowerCase();
}

/// A search whose first answer may still be on its way.
class _Pending {
  _Pending(Future<FeedPage> search) {
    future = search
        .then<void>(
          (p) => page = p,
          onError: (Object e, StackTrace s) {
            error = e;
            trace = s;
          },
        )
        .whenComplete(() => done = true);
  }

  late final Future<void> future;
  FeedPage? page;
  Object? error;
  StackTrace? trace;
  bool done = false;
}

/// Several searches as one feed: their videos interleaved (one from each
/// in turn) and each video shown once, also across pages.
///
/// Quick to show and light on data: the first page doesn't wait for the
/// slowest search (only [grace] after the first answer; a late search's
/// videos come on the next page, no new request), and each further page
/// asks only [advancePerPage] searches for more, taking turns.
class MixedFeedPage implements FeedPage {
  MixedFeedPage._(this.videos, this._sources, this._late, this._seen);

  @override
  final List<Video> videos;
  final List<FeedPage> _sources;
  final List<_Pending> _late;
  final Set<String> _seen;

  /// How long the first page waits for the other searches once one has
  /// answered.
  static const grace = Duration(milliseconds: 1500);

  /// Searches asked for more per page while scrolling.
  static const advancePerPage = 2;

  /// Pages of nothing but repeats before a scroll gives up.
  static const maxRepeatPages = 12;

  /// Runs [queries] through [search] at once. Searches that fail are left
  /// out; only when all fail does the error come through.
  static Future<MixedFeedPage> load(
    Iterable<String> queries,
    Future<FeedPage> Function(String query) search, {
    Duration grace = MixedFeedPage.grace,
  }) async {
    final pending = [for (final q in queries) _Pending(search(q))];
    final all = Future.wait([for (final p in pending) p.future]);
    final firstAnswer = Completer<void>();
    for (final p in pending) {
      p.future.then((_) {
        if (p.page != null && !firstAnswer.isCompleted) firstAnswer.complete();
      });
    }
    await Future.any([all, firstAnswer.future]);
    if (pending.any((p) => !p.done)) {
      final waited = Completer<void>();
      final timer = Timer(grace, waited.complete);
      await Future.any([all, waited.future]);
      timer.cancel();
    }
    final sources = [
      for (final p in pending)
        if (p.done) ?p.page,
    ];
    final late = [
      for (final p in pending)
        if (!p.done) p,
    ];
    if (sources.isEmpty && late.isEmpty) {
      final failed = pending.firstWhere((p) => p.error != null, orElse: () => pending.first);
      if (failed.error != null) Error.throwWithStackTrace(failed.error!, failed.trace!);
    }
    final seen = <String>{};
    return MixedFeedPage._(_interleave(sources, seen), sources, late, seen);
  }

  /// Null when every search has run out.
  @override
  Future<MixedFeedPage?> nextPage() async {
    final seen = {..._seen};
    // Searches that answered after the first page: their videos haven't
    // been shown yet, and need no new request.
    final arrived = [
      for (final p in _late)
        if (p.done) ?p.page,
    ];
    var late = [
      for (final p in _late)
        if (!p.done) p,
    ];
    if (arrived.isNotEmpty) {
      final videos = _interleave(arrived, seen);
      if (videos.isNotEmpty) return MixedFeedPage._(videos, [..._sources, ...arrived], late, seen);
    }
    var sources = [..._sources, ...arrived];
    // A page can be all repeats: keep going while any search has more (the
    // cap only guards against a search that answers the same page forever).
    for (var tries = 0; tries < maxRepeatPages && sources.isNotEmpty; tries++) {
      // The first few in line; they go to the back after (taking turns).
      final picked = sources.take(advancePerPage).toList();
      final next = await Future.wait([
        for (final p in picked) p.nextPage().then<FeedPage?>((n) => n, onError: (Object _) => null), // that search ends
      ]);
      final advanced = [...next.nonNulls];
      sources = [...sources.skip(picked.length), ...advanced];
      final videos = _interleave(advanced, seen);
      if (videos.isNotEmpty) return MixedFeedPage._(videos, sources, late, seen);
    }
    // Nothing new from the others: wait for searches still answering, and
    // keep every search that still has pages.
    if (late.isNotEmpty) {
      await Future.wait([for (final p in late) p.future]);
      final last = [for (final p in late) ?p.page];
      late = const [];
      final videos = _interleave(last, seen);
      if (videos.isNotEmpty) return MixedFeedPage._(videos, [...sources, ...last], late, seen);
    }
    return null;
  }

  static List<Video> _interleave(List<FeedPage> pages, Set<String> seen) {
    final lists = [for (final p in pages) p.videos.iterator];
    final out = <Video>[];
    var more = true;
    while (more) {
      more = false;
      for (final it in lists) {
        if (!it.moveNext()) continue;
        more = true;
        if (seen.add(it.current.id.value)) out.add(it.current);
      }
    }
    return out;
  }
}

/// Why a signed-in user sees the general feed instead of their YouTube
/// home, and what they can do about it.
enum HomeFeedAction { retry, signIn }

typedef HomeFeedNotice = ({String message, HomeFeedAction action});

/// The notice for a YouTube home that came back empty ([error] null: watch
/// history off) or failed.
HomeFeedNotice accountHomeNotice(Object? error) => switch (error) {
  null => (
    message: 'Your YouTube home has no recommendations (watch history may be off). Showing popular videos.',
    action: HomeFeedAction.retry,
  ),
  SignInExpired() => (message: 'Your YouTube sign-in expired. Showing popular videos.', action: HomeFeedAction.signIn),
  _ => (message: "Couldn't load your YouTube home. Showing popular videos.", action: HomeFeedAction.retry),
};

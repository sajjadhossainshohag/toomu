import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube/account_feed.dart';
import 'package:toomu/app/data/providers/youtube/feed_mix.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _video(String id) => Video(
  VideoId(id),
  id,
  'Author',
  ChannelId('UC${'b' * 22}'),
  null,
  '2 days ago',
  null,
  '',
  const Duration(minutes: 4),
  ThumbnailSet(id),
  null,
  const Engagement(1000, null, null),
  false,
);

/// A search's pages: [pages] of 3 videos each, ids like "aa00000000p".
/// Counts how many times more was asked for.
class _Search implements FeedPage {
  _Search(this.name, {this.page = 0, this.pages = 3, required this.asked});

  final String name;
  final int page;
  final int pages;
  final Map<String, int> asked;

  @override
  List<Video> get videos => [for (var i = 0; i < 3; i++) _video('$name${'0' * 7}$page$i'.substring(0, 11))];

  @override
  Future<FeedPage?> nextPage() async {
    asked[name] = (asked[name] ?? 0) + 1;
    return page + 1 < pages ? _Search(name, page: page + 1, pages: pages, asked: asked) : null;
  }
}

String _topic(Video v) => v.id.value.substring(0, 2);

void main() {
  const fast = Duration(milliseconds: 30);

  group('first page', () {
    test('does not wait for the slowest search', () async {
      final asked = <String, int>{};
      final slow = Completer<FeedPage>();
      final calls = <String>[];
      Future<FeedPage> search(String q) {
        calls.add(q);
        return q == 'bb' ? slow.future : Future.value(_Search(q, asked: asked));
      }

      final sw = Stopwatch()..start();
      final page = await MixedFeedPage.load(['aa', 'bb', 'cc'], search, grace: fast);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      expect(page.videos.map(_topic).toSet(), {'aa', 'cc'});

      // The slow one answers later: its videos come on the next page, with
      // no second request.
      slow.complete(_Search('bb', asked: asked));
      await Future<void>.delayed(Duration.zero);
      final next = (await page.nextPage())!;
      expect(next.videos.map(_topic).toSet(), {'bb'});
      expect(calls.where((q) => q == 'bb'), hasLength(1));
      expect(asked, isEmpty, reason: 'no search was asked for more yet');
    });

    test('waits a moment for the others, so the first page is still a mix', () async {
      final asked = <String, int>{};
      Future<FeedPage> search(String q) async {
        if (q == 'bb') await Future<void>.delayed(const Duration(milliseconds: 20));
        return _Search(q, asked: asked);
      }

      final page = await MixedFeedPage.load(['aa', 'bb'], search, grace: const Duration(milliseconds: 500));
      expect(page.videos.map(_topic).toSet(), {'aa', 'bb'});
    });

    test('one failed search is left out; all failing shows the error', () async {
      final asked = <String, int>{};
      final page = await MixedFeedPage.load(['aa', 'bb'], (q) async {
        if (q == 'bb') throw const SocketException('down');
        return _Search(q, asked: asked);
      }, grace: fast);
      expect(page.videos.map(_topic).toSet(), {'aa'});

      await expectLater(
        MixedFeedPage.load(['aa', 'bb'], (_) async => throw const SocketException('offline'), grace: fast),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('scrolling', () {
    test('each page asks only two searches for more, taking turns', () async {
      final asked = <String, int>{};
      final page = await MixedFeedPage.load(
        ['aa', 'bb', 'cc', 'dd'],
        (q) async => _Search(q, pages: 10, asked: asked),
        grace: fast,
      );
      final second = (await page.nextPage())!;
      expect(asked.values.fold(0, (a, b) => a + b), 2, reason: 'two requests, not four');
      expect(second.videos.map(_topic).toSet(), {'aa', 'bb'});

      final third = (await second.nextPage())!;
      expect(third.videos.map(_topic).toSet(), {'cc', 'dd'}, reason: 'then the other two');
      expect(asked, {'aa': 1, 'bb': 1, 'cc': 1, 'dd': 1});
    });

    test('ends when every search has run out, without repeating videos', () async {
      final asked = <String, int>{};
      FeedPage? page = await MixedFeedPage.load(
        ['aa', 'bb'],
        (q) async => _Search(q, pages: 2, asked: asked),
        grace: fast,
      );
      final seen = <String>[];
      while (page != null) {
        seen.addAll(page.videos.map((v) => v.id.value));
        page = await page.nextPage();
      }
      expect(seen.length, 12, reason: '2 searches × 2 pages × 3 videos');
      expect(seen.toSet(), hasLength(seen.length));
    });
  });

  group('signed in, shown the general feed', () {
    test('an expired sign-in says so and offers to sign in again', () {
      final n = accountHomeNotice(SignInExpired());
      expect(n.action, HomeFeedAction.signIn);
      expect(n.message, contains('sign-in expired'));
    });

    test('an empty home points at watch history; a failure offers a retry', () {
      expect(accountHomeNotice(null).message, contains('watch history'));
      expect(accountHomeNotice(null).action, HomeFeedAction.retry);
      final failed = accountHomeNotice(const SocketException('offline'));
      expect(failed.action, HomeFeedAction.retry);
      expect(failed.message, contains("Couldn't load your YouTube home"));
    });
  });
}

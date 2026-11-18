import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/core/values/app_constants.dart';
import 'package:toomu/app/data/providers/youtube/account_feed.dart';
import 'package:toomu/app/data/providers/youtube/feed_mix.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

Video _video(String id, String title) => Video(
  VideoId(id),
  title,
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

class _Page implements FeedPage {
  _Page(this.videos, [this._next]);

  @override
  final List<Video> videos;
  final Future<FeedPage?> Function()? _next;

  @override
  Future<FeedPage?> nextPage() async => _next?.call();
}

/// YouTube search without the network: every query answers its own videos
/// (plus one video every topic shares) and remembers what was asked.
class _FakeSearch {
  final queries = <String>[];
  final topicOf = <String, String>{};
  final _codes = <String, int>{};

  static const shared = 'sharedVideo';

  Future<FeedPage> call(String query) async {
    if (!query.endsWith(" #shorts")) queries.add(query); // the feed's searches, not the Shorts shelf's
    return _page(query, 0);
  }

  FeedPage _page(String query, int page) {
    final code = _codes.putIfAbsent(query, () => _codes.length);
    final videos = <Video>[
      if (page == 0) _video(shared, 'Everywhere'),
      for (var i = 0; i < 5; i++)
        _video('v${code.toString().padLeft(4, '0')}${(page * 10 + i).toString().padLeft(6, '0')}', '$query #$i'),
    ];
    for (final v in videos) {
      if (v.id.value != shared) topicOf[v.id.value] = query;
    }
    return _Page(videos, page < 2 ? () async => _page(query, page + 1) : null);
  }
}

class _FakeAccount extends AccountFeed {
  _FakeAccount(this.onHome) : super(() async => const {});

  Future<AccountFeedPage?> Function(AccountFeed feed) onHome;
  int homeCalls = 0;

  @override
  Future<AccountFeedPage?> home() {
    homeCalls++;
    return onHome(this);
  }

  @override
  Future<AccountFeedPage> subscriptions() async => AccountFeedPage(this, [_video('subsVid0001', 'From a channel')], null);
}

void main() {
  late Directory dir;
  var box = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() async {
    // GetStorage saves (and backs up) in the background, after write()
    // returns: let the last test's saves land before the folder goes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await deleteTempStorageDir(dir);
  });

  setUp(() async {
    Get.put(StorageService(await tempBox('home_feed_variety_${box++}', dir)));
    Get.put(YoutubeAccountService());
    Get.put(RemoteConfigService());
  });
  tearDown(Get.reset);

  YoutubeController open({required int seed, required _FakeSearch search, AccountFeed? account}) {
    Get.delete<YoutubeController>(force: true);
    return Get.put(YoutubeController(random: Random(seed), search: search.call, account: account));
  }

  test('home feed does not always show the same 2-3 topics', () async {
    final search = _FakeSearch();
    final launches = <Set<String>>[];
    for (var seed = 1; seed <= 5; seed++) {
      search.queries.clear();
      final yt = open(seed: seed, search: search);
      await yt.loadFeed();
      launches.add(search.queries.toSet());

      // One launch mixes several topics, interleaved, each video once.
      final firstTopics = yt.feed.take(8).map((v) => search.topicOf[v.id.value]).whereType<String>().toSet();
      expect(firstTopics.length, greaterThanOrEqualTo(3), reason: 'launch $seed: ${search.queries}');
      expect(yt.feed.where((v) => v.id.value == _FakeSearch.shared), hasLength(1));
    }

    for (final topics in launches) {
      expect(topics.length, greaterThanOrEqualTo(3), reason: 'every launch mixes topics: $launches');
    }
    for (var i = 1; i < launches.length; i++) {
      expect(launches[i], isNot(equals(launches[i - 1])), reason: 'launch ${i + 1} repeats the last one');
    }
    expect(
      launches.expand((t) => t).toSet().length,
      greaterThanOrEqualTo(10),
      reason: 'five launches cover many topics: $launches',
    );
  });

  test('home feed also follows what the user searched', () async {
    StorageService.to.write(AppConstants.kSearchHistory, ['tabla lessons', 'chess openings']);
    final search = _FakeSearch();
    final yt = open(seed: 7, search: search);
    await yt.loadFeed();

    expect(search.queries.toSet().intersection({'tabla lessons', 'chess openings'}), isNotEmpty);
    expect(search.queries.toSet().length, greaterThanOrEqualTo(3), reason: 'not only the last search');
  });

  test('a category tab is not the same single search every time', () async {
    final search = _FakeSearch();
    final asked = <String>{};
    for (var seed = 1; seed <= 4; seed++) {
      search.queries.clear();
      final yt = open(seed: seed, search: search);
      final music = yt.categories.indexWhere((c) => c.label == 'Music');
      yt.feedIndex.value = music;
      await yt.loadFeed();
      asked.addAll(search.queries);
    }
    expect(asked.length, greaterThan(2), reason: '$asked');
  });

  test('remote config categories can list several searches each', () async {
    StorageService.to.write(
      AppConstants.kRemoteConfig,
      '{"feedCategories": [{"label": "Bangla", "queries": ["bangla natok", "bangla song"]},'
      ' {"label": "Cricket", "query": "cricket highlights"}, {"label": "Empty"}]}',
    );
    Get.delete<RemoteConfigService>(force: true);
    Get.put(RemoteConfigService().init());
    final search = _FakeSearch();
    final yt = open(seed: 1, search: search);

    expect(yt.categories.map((c) => c.label), ['For you', 'Bangla', 'Cricket']);
    yt.feedIndex.value = 1;
    await yt.loadFeed();
    expect(search.queries.toSet(), {'bangla natok', 'bangla song'});
  });

  test('loading more of the mixed feed keeps mixing without repeats', () async {
    final search = _FakeSearch();
    final yt = open(seed: 3, search: search);
    await yt.loadFeed();
    final before = yt.feed.length;
    await yt.loadMoreFeed();

    expect(yt.feed.length, greaterThan(before));
    final ids = yt.feed.map((v) => v.id.value).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('signed-in user gets their own YouTube home feed', () async {
    YoutubeAccountService.to.signedIn.value = true;
    final search = _FakeSearch();
    final account = _FakeAccount(
      (feed) async => AccountFeedPage(
        feed,
        [_video('myHomeVid01', 'Mine 1'), _video('myHomeVid02', 'Mine 2')],
        null,
        chips: const [AccountChip('Cricket', 'CRICKET')],
      ),
    );
    final yt = open(seed: 1, search: search, account: account);
    await yt.loadFeed();

    expect(yt.categories.map((c) => c.label), ['Home', 'Subscriptions', 'Cricket']);
    expect(yt.feed.map((v) => v.id.value), ['myHomeVid01', 'myHomeVid02']);
    expect(search.queries, isEmpty);
    expect(yt.feedError.value, isNull);
  });

  test('signed-in user still gets a varied feed when their YouTube home fails', () async {
    YoutubeAccountService.to.signedIn.value = true;
    final search = _FakeSearch();
    final account = _FakeAccount((_) async => throw const SocketException('offline'));
    final yt = open(seed: 2, search: search, account: account);
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);

    expect(yt.feedError.value, isNull);
    expect(yt.feed, isNotEmpty);
    expect(search.queries.toSet().length, greaterThanOrEqualTo(3));
  });

  test('signed-in user with an empty YouTube home gets the varied feed', () async {
    YoutubeAccountService.to.signedIn.value = true;
    final search = _FakeSearch();
    final yt = open(seed: 4, search: search, account: _FakeAccount((_) async => null));
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);

    expect(yt.feed, isNotEmpty);
    expect(search.queries.toSet().length, greaterThanOrEqualTo(3));
  });

  test('pull to refresh tries the signed-in home again after a failure', () async {
    YoutubeAccountService.to.signedIn.value = true;
    final search = _FakeSearch();
    var fail = true;
    final account = _FakeAccount((feed) async {
      if (fail) throw const SocketException('offline');
      return AccountFeedPage(feed, [_video('myHomeVid01', 'Mine')], null);
    });
    final yt = open(seed: 5, search: search, account: account);
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);

    fail = false;
    await yt.loadFeed(refresh: true);
    await Future<void>.delayed(Duration.zero);

    expect(account.homeCalls, 2);
    expect(yt.categories.first.label, 'Home');
    expect(yt.feed.map((v) => v.id.value), ['myHomeVid01']);
  });

  group('feed UX', () {
    test('the feed on screen at launch is not swapped for the new mix; it goes below', () async {
      final search = _FakeSearch();
      final yt = open(seed: 3, search: search);
      yt.feed.assignAll([_video('savedVid001', 'Saved 1'), _video('savedVid002', 'Saved 2')]);
      await yt.loadFeed(refresh: true, keepShown: true);
      expect(yt.feed.take(2).map((v) => v.id.value), ['savedVid001', 'savedVid002']);
      expect(yt.feed.length, greaterThan(2), reason: 'the new mix follows');
      final ids = yt.feed.map((v) => v.id.value).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'no video twice');
    });

    test('pull to refresh still replaces the feed', () async {
      final yt = open(seed: 3, search: _FakeSearch());
      yt.feed.assignAll([_video('savedVid001', 'Saved 1')]);
      await yt.loadFeed(refresh: true);
      expect(yt.feed.map((v) => v.id.value), isNot(contains('savedVid001')));
    });

    test('signed in with an expired sign-in: told so, with a way to sign in again', () async {
      YoutubeAccountService.to.signedIn.value = true;
      final yt = open(seed: 2, search: _FakeSearch(), account: _FakeAccount((_) async => throw SignInExpired()));
      await yt.loadFeed();
      await Future<void>.delayed(Duration.zero);
      expect(yt.feed, isNotEmpty, reason: 'the general feed meanwhile');
      expect(yt.feedNotice.value?.action, HomeFeedAction.signIn);
    });

    test('signed in with an empty or failing home: told why, with Retry', () async {
      YoutubeAccountService.to.signedIn.value = true;
      final empty = open(seed: 4, search: _FakeSearch(), account: _FakeAccount((_) async => null));
      await empty.loadFeed();
      await Future<void>.delayed(Duration.zero);
      expect(empty.feedNotice.value?.message, contains('watch history'));
      expect(empty.feedNotice.value?.action, HomeFeedAction.retry);

      final offline = open(
        seed: 5,
        search: _FakeSearch(),
        account: _FakeAccount((_) async => throw const SocketException('offline')),
      );
      await offline.loadFeed();
      await Future<void>.delayed(Duration.zero);
      expect(offline.feedNotice.value?.action, HomeFeedAction.retry);
    });

    test('the notice goes once their home loads, and on signing out', () async {
      YoutubeAccountService.to.signedIn.value = true;
      var fail = true;
      final account = _FakeAccount((feed) async {
        if (fail) throw const SocketException('offline');
        return AccountFeedPage(feed, [_video('myHomeVid01', 'Mine')], null);
      });
      final yt = open(seed: 6, search: _FakeSearch(), account: account);
      await yt.loadFeed();
      await Future<void>.delayed(Duration.zero);
      expect(yt.feedNotice.value, isNotNull);

      fail = false;
      await yt.onFeedNotice(); // Retry
      await Future<void>.delayed(Duration.zero);
      expect(yt.feedNotice.value, isNull);
      expect(yt.feed.map((v) => v.id.value), ['myHomeVid01']);

      fail = true;
      await yt.loadFeed(refresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(yt.feedNotice.value, isNotNull);
      YoutubeAccountService.to.signedIn.value = false;
      await Future<void>.delayed(Duration.zero);
      expect(yt.feedNotice.value, isNull);
    });
  });

  test("each tab's Shorts shelf comes from a Shorts search on its topic, and keeps only Shorts-length videos", () async {
    final search = _FakeSearch();
    final yt = Get.put(YoutubeController(
      random: Random(1),
      search: (q) async => q.endsWith('#shorts')
          ? _Page([
              Video(VideoId('shortaaaaaa'), q, 'Author', ChannelId('UC${'b' * 22}'), null, null, null, '',
                  const Duration(seconds: 40), ThumbnailSet('shortaaaaaa'), null, const Engagement(1, null, null), false),
              _video('longaaaaaaa', 'Long one'),
            ])
          : search(q),
    ));
    final music = yt.categories.indexWhere((c) => c.label == 'Music');
    yt.selectCategory(music);
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);

    expect(yt.shorts.map((v) => v.id.value), ['shortaaaaaa']);
    expect(yt.categories[music].queries, contains(yt.shorts.single.title.replaceAll(' #shorts', '')));

    yt.selectCategory(0);
    expect(yt.shorts, isEmpty, reason: "another tab doesn't show Music's Shorts");
  });

  test("a signed-in Home's Shorts come from YouTube's topics for the account, not what's trending", () async {
    YoutubeAccountService.to.signedIn.value = true;
    final asked = <String>[];
    final account = _FakeAccount(
      (feed) async => AccountFeedPage(
        feed,
        [_video('myHomeVid01', 'This is The Most Mouth Watering Street food of Dhaka!')],
        null,
        chips: const [AccountChip('Recently uploaded', 'NEW'), AccountChip('Cricket', 'CRICKET')],
      ),
    );
    final yt = Get.put(YoutubeController(
      random: Random(1),
      search: (q) async {
        asked.add(q);
        return _Page(const []);
      },
      account: account,
    ));
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);
    expect(asked, ['Cricket #shorts'], reason: 'a whole video title as the search found no Shorts on YouTube');

    asked.clear();
    yt.feedIndex.value = 1;
    await yt.loadFeed();
    await Future<void>.delayed(Duration.zero);
    expect(asked, ['Author #shorts'], reason: 'Subscriptions: Shorts from a channel the user follows');
  });
}

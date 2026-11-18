import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/tiktok_item.dart';
import 'package:toomu/app/data/providers/tiktok/tiktok_feed.dart';
import 'package:toomu/app/modules/tiktok/controllers/tiktok_controller.dart';
import 'package:toomu/app/modules/tiktok/controllers/tiktok_feeds.dart';
import 'package:toomu/app/modules/tiktok/tiktok_prefetch.dart';
import 'package:toomu/app/modules/tiktok/views/tiktok_seek_bar.dart';
import 'package:toomu/app/services/tiktok_account_service.dart';
import 'package:toomu/app/modules/tiktok/views/tiktok_view.dart';
import 'package:toomu/app/services/video_session_service.dart';

Map<String, dynamic> _json(String id, {Map<String, dynamic> video = const {}, Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'desc': 'Caption $id',
      'video': {'playAddr': 'https://v16.tiktok.com/$id.mp4', 'width': 576, 'height': 1024, 'duration': 9, ...video},
      'author': {'uniqueId': 'user$id', 'nickname': 'User $id', 'avatarThumb': 'small', 'avatarMedium': 'medium'},
      'stats': {'diggCount': 1200},
      ...extra,
    };

TiktokItem _video(String id) => TiktokItem(id: id, authorId: 'a', playUrl: 'https://v/$id.mp4');

class _Source implements TiktokFeedSource {
  final _out = StreamController<List<TiktokItem>>.broadcast(sync: true);
  int starts = 0, mores = 0, closes = 0;
  Object? failStart;
  final pageView = ValueNotifier<Widget?>(null);

  @override
  ValueListenable<Widget?> get page => pageView;

  @override
  Stream<List<TiktokItem>> get batches => _out.stream;

  @override
  Future<void> start() async {
    starts++;
    if (failStart != null) throw failStart!;
  }

  @override
  Future<void> more() async => mores++;

  @override
  Future<void> close() async => closes++;

  final active = <bool>[];
  final background = <bool>[];

  @override
  void setActive(bool on, {bool background = false}) {
    active.add(on);
    this.background.add(background);
  }

  void send(List<String> ids) => _out.add([for (final id in ids) _video(id)]);
}

class _Playback implements TiktokPlayback {
  final log = <String>[];
  final gates = <String, Completer<void>>{};
  String? held;

  @override
  Future<void> play(TiktokItem item) async {
    log.add('play ${item.id}');
    await gates[item.id]?.future;
    held = item.id;
  }

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<void> stop() async {
    log.add('stop');
    held = null;
  }

  @override
  bool holds(TiktokItem item) => held == item.id;
}

class _Prefetch implements TiktokPrefetcher {
  final wanted = <List<String>>[];
  int clears = 0;

  @override
  void want(List<TiktokItem> items) => wanted.add([for (final i in items) i.id]);

  @override
  Future<void> clear() async => clears++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feed data', () {
    test('a feed batch gives its videos without the ads, slideshows and file-less entries', () {
      final batch = jsonEncode({
        'itemList': [
          _json('1'),
          _json('2', extra: {'isAd': true}),
          _json('3', extra: {'adLabelVersion': 1}),
          _json('4', extra: {'imagePost': {'images': []}}),
          _json('5', video: {'playAddr': ''}),
          _json('6'),
        ],
        'hasMore': true,
      });
      final items = TiktokFeed.parse('feed', batch);
      expect(items.map((i) => i.id), ['1', '6']);
      expect(items.first.avatarUrl, 'medium');
    });

    test("the For You page's own first videos are read too", () {
      final page = jsonEncode({
        '__DEFAULT_SCOPE__': {
          'webapp.foryou.video': {
            'itemList': [_json('7'), _json('8')],
          },
        },
      });
      expect(TiktokFeed.parse('page', page).map((i) => i.id), ['7', '8']);
    });

    test('unreadable or unexpected data gives no videos (no crash)', () {
      expect(TiktokFeed.parse('feed', 'not json'), isEmpty);
      expect(TiktokFeed.parse('feed', '[]'), isEmpty);
      expect(TiktokFeed.parse('page', '{"__DEFAULT_SCOPE__": 3}'), isEmpty);
      expect(TiktokFeed.parse('feed', '{"itemList": [1, "x", null]}'), isEmpty);
    });

    test('the best H.264 quality plays (not H.265, which some phones cannot decode)', () {
      Map<String, dynamic> gear(String codec, int rate, String url) => {
            'CodecType': codec,
            'Bitrate': rate,
            'PlayAddr': {
              'UrlList': [url, '$url-mirror'],
            },
          };
      final item = TiktokItem.fromJson(_json('9', video: {
        'bitrateInfo': [
          gear('h264', 400000, 'low264'),
          gear('h265_hvc1', 900000, 'best265'),
          gear('h264', 800000, 'best264'),
        ],
      }));
      expect(item?.playUrl, 'best264');
      expect(TiktokItem.fromJson(_json('10'))?.playUrl, 'https://v16.tiktok.com/10.mp4');
    });
  });

  group('TikTok tab', () {
    late _Source source;
    late _Playback playback;
    late RxInt tabIndex;

    late _Prefetch prefetch;

    TiktokController make({int shownTab = 0}) {
      tabIndex = shownTab.obs;
      return Get.put(
        TiktokController(source: source, playback: playback, tabIndex: tabIndex, tab: 0, prefetch: prefetch),
      );
    }

    setUp(() {
      source = _Source();
      playback = _Playback();
      prefetch = _Prefetch();
      TiktokController.startTimeout = const Duration(milliseconds: 60);
      TiktokController.idleClose = const Duration(milliseconds: 60);
      TiktokController.moreRetry = const Duration(milliseconds: 60);
    });

    tearDown(Get.reset);

    test('the first video plays as soon as the feed answers', () async {
      final c = make();
      expect(source.starts, 1);
      source.send(['1', '2']);
      await pumpEventQueue();
      expect(playback.log, ['play 1']);
      expect(c.playing.value, '1');
    });

    test('swiping is quick: the first seconds of the next four videos download while one plays', () async {
      final c = make();
      source.send(['1', '2', '3', '4', '5', '6']);
      await pumpEventQueue();
      expect(prefetch.wanted.last, ['2', '3', '4', '5']);
      await c.show(1);
      expect(prefetch.wanted.last, ['3', '4', '5', '6']);
      await c.show(5);
      expect(prefetch.wanted.last, isEmpty);
      source.send(['7']);
      await pumpEventQueue();
      expect(prefetch.wanted.last, ['7'], reason: 'a new batch arriving at the end is fetched too');
    });

    test('the next videos download only once the one on screen plays (no fight for the connection)', () async {
      final c = make();
      playback.gates['1'] = Completer<void>();
      source.send(['1', '2', '3', '4', '5', '6']);
      await pumpEventQueue();
      expect(c.opening.value, isTrue);
      expect(prefetch.wanted, isEmpty, reason: 'video 1 is still starting');
      playback.gates['1']!.complete();
      await pumpEventQueue();
      expect(prefetch.wanted.last, ['2', '3', '4', '5']);
    });

    test('a video swiped past before it played downloads nothing ahead', () async {
      final c = make();
      playback.gates['2'] = Completer<void>();
      source.send(['1', '2', '3', '4', '5', '6', '7', '8']);
      await pumpEventQueue();
      final skipped = c.show(1);
      await c.show(2);
      playback.gates['2']!.complete();
      await skipped;
      expect(prefetch.wanted.map((w) => w.first), ['2', '4'], reason: 'after video 1 and video 3, not video 2');
    });

    test("TikTok's page pauses while the app is in the background and runs again when it is back", () async {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      make();
      source.send(['1']);
      await pumpEventQueue();
      expect(source.active.last, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(source.active.last, isFalse);
      expect(source.background.last, isTrue, reason: 'the app is hidden: its scripts stop too');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(source.active.last, isTrue);
    });

    test("TikTok's page pauses while another tab is shown", () async {
      make();
      await pumpEventQueue();
      tabIndex.value = 2;
      expect(source.active.last, isFalse);
      expect(source.background.last, isFalse, reason: 'the browser may be open: other pages keep their scripts');
      tabIndex.value = 0;
      expect(source.active.last, isTrue);
    });

    test('downloaded videos are deleted when the tab is closed for good', () async {
      make();
      await Get.delete<TiktokController>();
      expect(prefetch.clears, 1);
    });

    test('nothing loads or plays until the TikTok tab is opened', () async {
      final c = make(shownTab: 3);
      await pumpEventQueue();
      expect(source.starts, 0);
      tabIndex.value = 0;
      source.send(['1']);
      await pumpEventQueue();
      expect(source.starts, 1);
      expect(c.playing.value, '1');
    });

    test('leaving the tab stops the video; coming back plays it again', () async {
      final c = make();
      source.send(['1', '2']);
      await pumpEventQueue();
      tabIndex.value = 2;
      await pumpEventQueue();
      expect(playback.log.last, 'stop');
      expect(c.playing.value, isNull);
      tabIndex.value = 0;
      await pumpEventQueue();
      expect(playback.log.last, 'play 1');
      expect(c.playing.value, '1');
    });

    test('a quick swipe past videos plays only the last one', () async {
      final c = make();
      playback.gates['2'] = Completer<void>();
      source.send(['1', '2', '3', '4', '5', '6', '7', '8']);
      await pumpEventQueue();
      unawaited(c.show(1));
      final last = c.show(2);
      playback.gates['2']!.complete();
      await last;
      await pumpEventQueue();
      expect(c.playing.value, '3');
      expect(c.page.value, 2);
    });

    test('more videos are asked for near the end, once until they arrive', () async {
      final c = make();
      source.send(['1', '2', '3', '4', '5', '6', '7', '8']);
      await pumpEventQueue();
      expect(source.mores, 0);
      await c.show(4); // 4 left
      await c.show(5);
      expect(source.mores, 1);
      source.send(['9', '10']);
      await c.show(6);
      expect(source.mores, 2);
      expect(c.items.length, 10);
    });

    test('a request for more that brings nothing is repeated later', () async {
      final c = make();
      source.send(['1', '2']);
      await pumpEventQueue();
      expect(source.mores, 1);
      await c.show(1);
      expect(source.mores, 1);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await c.show(0);
      expect(source.mores, 2);
    });

    test('a video TikTok hands out again shows only once', () async {
      final c = make();
      source.send(['1', '2']);
      source.send(['2', '3', '1']);
      await pumpEventQueue();
      expect(c.items.map((i) => i.id), ['1', '2', '3']);
    });

    test("a feed that never answers shows an error, and Try again loads it afresh", () async {
      final c = make();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(c.feedError.value, isNotNull);
      await c.retry();
      expect(source.closes, 1);
      expect(source.starts, 2);
      expect(c.feedError.value, isNull);
      source.send(['1']);
      await pumpEventQueue();
      expect(c.playing.value, '1');
    });

    test('a feed that fails to start says so at once', () async {
      source.failStart = Exception('no network');
      final c = make();
      await pumpEventQueue();
      expect(c.feedError.value, isNotNull);
    });

    test("TikTok's hidden page closes a while after leaving the tab", () async {
      make();
      source.send(['1']);
      await pumpEventQueue();
      tabIndex.value = 1;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(source.closes, 1);
    });

    test('tap pauses and plays; after another screen took the player it opens the video again', () async {
      final c = make();
      source.send(['1']);
      await pumpEventQueue();
      await c.togglePause();
      expect(playback.log.last, 'pause');
      expect(c.paused.value, isTrue);
      await c.togglePause();
      expect(playback.log.last, 'resume');
      playback.held = 'youtube';
      await c.togglePause();
      expect(playback.log.last, 'play 1');
    });

    test('the video pauses while the app is hidden and carries on when it is back', () async {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      make();
      source.send(['1']);
      await pumpEventQueue();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(playback.log.last, 'pause');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(playback.log.last, 'resume');
    });
  });

  testWidgets("a TikTok video shows TikTok's layout: For You, author, caption, sound and the counts", (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(Get.reset);
    Get.put(VideoSessionService());
    final source = _Source();
    Get.put(TiktokController(source: source, playback: _Playback(), tabIndex: 0.obs, tab: 0));
    source._out.add([
      TiktokItem.fromJson({
        ..._json('1'),
        'desc': 'A very long caption ' * 10,
        'stats': {'diggCount': 35200, 'commentCount': 310, 'shareCount': 0},
        'music': {'title': 'original sound', 'authorName': 'tiff'},
      })!,
    ]);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TiktokFeedView())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('User 1'), findsOneWidget);
    expect(find.text('35.2K'), findsOneWidget);
    expect(find.text('310'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('original sound · tiff'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await Get.delete<TiktokController>(); // its timers end with it
  });

  testWidgets('more videos load after the first two: TikTok\'s page is drawn under the feed, not hidden', (tester) async {
    // On Android a hidden (invisible) WebView never draws, so TikTok's page
    // never loaded its next batches: only the page's own first two videos
    // showed. The page now sits in the tab, under the feed.
    addTearDown(Get.reset);
    Get.put(VideoSessionService());
    final source = _Source();
    Get.put(TiktokController(source: source, playback: _Playback(), tabIndex: 0.obs, tab: 0));
    source.pageView.value = const SizedBox(key: ValueKey('tiktok-page'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TiktokFeedView())));
    expect(find.byKey(const ValueKey('tiktok-page')), findsOneWidget);
    expect(find.text('Loading TikTok…'), findsOneWidget, reason: 'the feed covers the page');
    source._out.add([_video('1')]);
    await tester.pump();
    expect(find.byKey(const ValueKey('tiktok-page')), findsOneWidget, reason: 'still drawn while the videos show');
    source.pageView.value = null;
    await tester.pump();
    expect(find.byKey(const ValueKey('tiktok-page')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await Get.delete<TiktokController>();
  });

  test("TikTok's page is put on screen when the feed starts and taken away when it closes", () async {
    final source = WebTiktokFeedSource();
    expect(source.page.value, isNull);
    await source.start();
    expect(source.page.value, isNotNull);
    await source.start();
    final first = source.page.value;
    await source.start();
    expect(identical(source.page.value, first), isTrue, reason: 'one page, not a new one per call');
    await source.close();
    expect(source.page.value, isNull);
    await source.more();
    expect(source.page.value, isNotNull, reason: 'asking for more opens it again');
  });

  group('swiping', () {
    late _Source source;
    late _Playback playback;
    late TiktokController c;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Get.put(VideoSessionService());
      source = _Source();
      playback = _Playback();
      c = Get.put(TiktokController(source: source, playback: playback, tabIndex: 0.obs, tab: 0));
      addTearDown(Get.reset); // also when the test fails half way
      source.send(['1', '2', '3', '4', '5', '6']);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TiktokFeedView())));
      await tester.pump();
      expect(playback.log, ['play 1']);
    }

    // pumpAndSettle never ends: the sound disc turns while a video plays.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await Get.delete<TiktokController>();
      Get.reset();
    }

    testWidgets('scroll is smooth: the next video starts once the swipe settles, not halfway through it',
        (tester) async {
      await open(tester);
      final finger = await tester.startGesture(const Offset(180, 600));
      await finger.moveBy(const Offset(0, -20)); // wins the drag (this bit isn't scrolled)
      await tester.pump();
      await finger.moveBy(const Offset(0, -250));
      await tester.pump();
      await finger.moveBy(const Offset(0, -250)); // past half the screen, finger still down
      await tester.pump();
      expect(c.pages.page, greaterThan(0.6));
      await tester.pump();
      expect(playback.log, ['play 1'], reason: 'no player work while the page moves');
      await finger.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(playback.log, ['play 1'], reason: 'still snapping into place');
      await settle(tester);
      expect(playback.log, ['play 1', 'play 2']);
      expect(c.page.value, 1);
      await close(tester);
    });

    testWidgets('a swipe that falls back to the same video keeps it playing', (tester) async {
      await open(tester);
      final finger = await tester.startGesture(const Offset(180, 600));
      await finger.moveBy(const Offset(0, -100));
      await tester.pump();
      await finger.up();
      await settle(tester);
      expect(playback.log, ['play 1']);
      await close(tester);
    });

    testWidgets('a flick snaps to the next video quickly, like TikTok', (tester) async {
      await open(tester);
      await tester.fling(find.byType(PageView), const Offset(0, -120), 1500);
      await tester.pump(); // the snap starts
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.pages.page, closeTo(1, 0.02), reason: 'there within 200 ms');
      await settle(tester);
      await close(tester);
    });
  });

  test("TikTok's page is drawn as a texture: the feed scrolls over it without extra layers", () {
    expect(WebTiktokFeedSource.settings().useHybridComposition, isFalse);
  });

  group('TikTok account', () {
    test('signed in = TikTok set its session cookie', () {
      expect(TiktokAccountService.hasSession(['ttwid', 'msToken', 'tt_chain_token']), isFalse);
      expect(TiktokAccountService.hasSession(['ttwid', 'sessionid']), isTrue);
      expect(TiktokAccountService.hasSession(['sid_tt']), isTrue);
    });

    test("who is signed in is read from TikTok's page; a visitor's page has nobody", () {
      String page(Map<String, dynamic> context) => jsonEncode({
            '__DEFAULT_SCOPE__': {'webapp.app-context': context},
          });
      final u = TiktokFeed.userFrom(page({
        'user': {'uniqueId': 'shohag', 'nickName': 'Shohag', 'avatarUri': ['https://p16/a.jpg']},
      }));
      expect(u?.id, 'shohag');
      expect(u?.name, 'Shohag');
      expect(u?.avatar, 'https://p16/a.jpg');
      expect(TiktokFeed.userFrom(page({'wid': '1', 'odinId': '2'})), isNull);
      expect(TiktokFeed.userFrom('nonsense'), isNull);
    });

    test("the Following page's own first videos are read (whatever its data is called)", () {
      final page = jsonEncode({
        '__DEFAULT_SCOPE__': {
          'webapp.app-context': {'wid': '1'},
          'webapp.following.video': {
            'itemList': [_json('31'), _json('32')],
          },
        },
      });
      expect(TiktokFeed.parse('page', page).map((i) => i.id), ['31', '32']);
    });

    test('each feed page copies only its own feed requests', () {
      RegExp js(String api) => RegExp(api.replaceAll(r'\/', '/'));
      final forYou = js(WebTiktokFeedSource.forYouApi);
      final following = js(WebTiktokFeedSource.followingApi);
      const fy = 'https://www.tiktok.com/api/recommend/item_list/?aid=1988';
      const fo = 'https://www.tiktok.com/api/following/item_list/?aid=1988';
      const explore = 'https://www.tiktok.com/api/prefetch/explore/item_list/?aid=1988';
      expect(forYou.hasMatch(fy), isTrue);
      expect(forYou.hasMatch(fo), isFalse);
      expect(forYou.hasMatch(explore), isFalse);
      expect(following.hasMatch(fo), isTrue);
      expect(following.hasMatch(fy), isFalse);
      expect(following.hasMatch(explore), isFalse);
      expect(WebTiktokFeedSource.scriptFor(WebTiktokFeedSource.followingApi), contains('follow'));
      expect(WebTiktokFeedSource.scriptFor(WebTiktokFeedSource.forYouApi), isNot(contains('__API__')));
    });

    test('Following plays only when picked and signed in', () {
      final signedIn = false.obs;
      final feeds = Get.put(TiktokFeeds(signedIn: signedIn));
      addTearDown(Get.reset);
      expect(feeds.forYouShown.value, isTrue);
      feeds.pick(TiktokFeedKind.following);
      expect(feeds.forYouShown.value, isFalse);
      expect(feeds.followingShown.value, isFalse, reason: 'signed out: the sign-in prompt shows');
      signedIn.value = true;
      expect(feeds.followingShown.value, isTrue);
    });
  });

  group('two feeds', () {
    late _Source source;
    late _Playback playback;
    late RxBool shown;
    late RxBool account;

    TiktokController make() {
      source = _Source();
      playback = _Playback();
      shown = false.obs;
      account = false.obs;
      addTearDown(Get.reset);
      return Get.put(TiktokController(
        source: source,
        playback: playback,
        tabIndex: 0.obs,
        tab: 0,
        selected: shown,
        account: account,
      ));
    }

    test("a feed that isn't picked doesn't load or play", () async {
      final c = make();
      await pumpEventQueue();
      expect(source.starts, 0);
      shown.value = true;
      source.send(['1']);
      await pumpEventQueue();
      expect(c.playing.value, '1');
      shown.value = false;
      await pumpEventQueue();
      expect(playback.log.last, 'stop');
    });

    test('signing in or out starts the feed over (For You follows the account)', () async {
      final c = make();
      shown.value = true;
      source.send(['1', '2']);
      await pumpEventQueue();
      account.value = true;
      await pumpEventQueue();
      expect(c.items, isEmpty);
      expect(source.closes, 1);
      expect(source.starts, 2);
      source.send(['1', '9']);
      await pumpEventQueue();
      expect(c.items.map((i) => i.id), ['1', '9'], reason: 'the same video may come again for the account');
      expect(c.playing.value, '1');
    });
  });

  group('end of the feed', () {
    late _Source source;
    late _Playback playback;
    late TiktokController c;

    setUp(() async {
      TiktokController.moreRetry = const Duration(milliseconds: 40);
      source = _Source();
      playback = _Playback();
      c = Get.put(TiktokController(source: source, playback: playback, tabIndex: 0.obs, tab: 0));
      source.send(['1', '2']);
      await pumpEventQueue();
      await c.show(1);
    });

    tearDown(Get.reset);

    test('past the last video: it stops and TikTok\'s spinner shows while more are asked for', () async {
      final asked = source.mores;
      c.settled(2);
      await pumpEventQueue();
      expect(c.atEnd, isTrue);
      expect(playback.log.last, 'stop');
      expect(c.playing.value, isNull);
      expect(source.mores, greaterThan(asked));
    });

    test('when the next videos come, the first of them plays right there', () async {
      c.settled(2);
      await pumpEventQueue();
      source.send(['3', '4']);
      await pumpEventQueue();
      expect(c.page.value, 2);
      expect(c.playing.value, '3');
      expect(c.atEnd, isFalse);
    });

    test('it keeps asking, then says nothing came; Try again asks again', () async {
      c.settled(2);
      await pumpEventQueue();
      final first = source.mores;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(source.mores, first + TiktokController.endTries - 1);
      expect(c.endStuck.value, isTrue);
      c.retryEnd();
      expect(c.endStuck.value, isFalse);
      expect(source.mores, first + TiktokController.endTries);
      source.send(['5']);
      await pumpEventQueue();
      expect(c.playing.value, '5');
    });
  });

  group('seek bar', () {
    Future<List<Duration>> pumpBar(WidgetTester tester) async {
      final seeks = <Duration>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 300,
              child: TiktokSeekBar(
                position: const Stream<Duration>.empty(),
                initial: const Duration(seconds: 4),
                total: () => const Duration(seconds: 40),
                onSeek: (d) async => seeks.add(d),
              ),
            ),
          ),
        ),
      ));
      return seeks;
    }

    testWidgets('dragging along it moves the video, showing the time like TikTok', (tester) async {
      final seeks = await pumpBar(tester);
      final bar = tester.getRect(find.byType(GestureDetector).last);
      final finger = await tester.startGesture(Offset(bar.left + 30, bar.center.dy));
      await finger.moveBy(const Offset(20, 0));
      await tester.pump();
      await finger.moveTo(Offset(bar.left + 225, bar.center.dy));
      await tester.pump();
      expect(find.text('00:30 / 00:40', findRichText: true), findsOneWidget);
      expect(seeks, isEmpty, reason: 'it jumps when let go');
      await finger.up();
      await tester.pump();
      expect(seeks.single.inMilliseconds, closeTo(30000, 200));
      expect(find.text('00:30 / 00:40', findRichText: true), findsNothing);
    });

    testWidgets('a tap on it jumps there', (tester) async {
      final seeks = await pumpBar(tester);
      final bar = tester.getRect(find.byType(GestureDetector).last);
      await tester.tapAt(Offset(bar.left + 150, bar.center.dy));
      await tester.pump();
      expect(seeks.single, const Duration(seconds: 20));
    });

    test('a touch past either end goes to the start or the end', () {
      const total = Duration(seconds: 40);
      expect(TiktokSeekBar.target(-20, 300, total), Duration.zero);
      expect(TiktokSeekBar.target(400, 300, total), total);
      expect(TiktokSeekBar.target(10, 0, total), Duration.zero);
    });
  });

  testWidgets('Following, signed out, asks to sign in (TikTok does too); For You is picked first', (tester) async {
    addTearDown(Get.reset);
    Get.put(VideoSessionService());
    Get.put(TiktokAccountService());
    final feeds = Get.put(TiktokFeeds(signedIn: TiktokAccountService.to.signedIn));
    final source = _Source();
    Get.put(
      TiktokController(source: source, playback: _Playback(), tabIndex: 0.obs, tab: 0, selected: feeds.forYouShown),
      tag: TiktokFeeds.forYouTag,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TiktokView())));
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Loading TikTok…'), findsOneWidget);
    expect(source.starts, 1);
    expect(find.byTooltip('Refresh'), findsNothing, reason: 'no refresh button: pull or double tap');
    await tester.tap(find.text('For You'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('For You'));
    await tester.pump();
    expect(source.closes, 1, reason: 'a double tap on "For You" starts it over with fresh videos');
    expect(source.starts, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Following'));
    await tester.pump();
    expect(find.text('Videos from accounts you follow'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byTooltip('Sign in to TikTok'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await Get.delete<TiktokController>(tag: TiktokFeeds.forYouTag);
  });

  test('one tap switches feeds at once; only a quick second tap refreshes', () async {
    final feeds = Get.put(TiktokFeeds(signedIn: true.obs));
    addTearDown(Get.reset);
    final source = _Source();
    Get.put(
      TiktokController(source: source, playback: _Playback(), tabIndex: 0.obs, tab: 0, selected: feeds.forYouShown),
      tag: TiktokFeeds.forYouTag,
    );
    final t0 = DateTime(2026);
    feeds.tap(TiktokFeedKind.following, now: t0);
    expect(feeds.feed.value, TiktokFeedKind.following, reason: 'no waiting for a second tap');
    feeds.tap(TiktokFeedKind.forYou, now: t0.add(const Duration(milliseconds: 100)));
    await pumpEventQueue();
    expect(source.closes, 0, reason: 'taps on two different feeds');
    feeds.tap(TiktokFeedKind.forYou, now: t0.add(const Duration(seconds: 2)));
    await pumpEventQueue();
    expect(source.closes, 0, reason: 'too slow for a double tap');
    feeds.tap(TiktokFeedKind.forYou, now: t0.add(const Duration(milliseconds: 2200)));
    await pumpEventQueue();
    expect(source.closes, 1);
    feeds.tap(TiktokFeedKind.forYou, now: t0.add(const Duration(milliseconds: 2400)));
    await pumpEventQueue();
    expect(source.closes, 1, reason: 'a third tap is a new first tap');
  });

  testWidgets('pulling down on the first video refreshes the feed', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(Get.reset);
    Get.put(VideoSessionService());
    final source = _Source();
    Get.put(TiktokController(source: source, playback: _Playback(), tabIndex: 0.obs, tab: 0));
    source.send(['1', '2']);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TiktokFeedView())));
    await tester.pump();
    await tester.fling(find.byType(PageView), const Offset(0, 400), 1000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(source.closes, 1);
    expect(source.starts, 2);
    await tester.pumpWidget(const SizedBox());
    await Get.delete<TiktokController>();
  });
}

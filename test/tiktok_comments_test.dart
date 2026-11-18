import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/tiktok_comment.dart';
import 'package:toomu/app/data/models/tiktok_item.dart';
import 'package:toomu/app/data/providers/tiktok/tiktok_video_page.dart';
import 'package:toomu/app/modules/tiktok/controllers/tiktok_actions.dart';
import 'package:toomu/app/modules/tiktok/controllers/tiktok_comments_controller.dart';
import 'package:toomu/app/modules/tiktok/views/tiktok_comments_sheet.dart';
import 'package:toomu/app/modules/tiktok/views/tiktok_sign_in_page.dart';
import 'package:toomu/app/modules/tiktok/views/tiktok_view.dart';

const _item = TiktokItem(
  id: '77',
  authorId: 'maker',
  playUrl: 'https://v/77.mp4',
  likes: 10,
  comments: 3,
);

Map<String, dynamic> _comment(
  String id, {
  int replies = 0,
  bool liked = false,
  String? by,
}) => {
  'cid': id,
  'text': 'Comment $id',
  'create_time': 1795000000,
  'digg_count': 5,
  'user_digged': liked ? 1 : 0,
  'reply_comment_total': replies,
  'is_author_digged': id == 'c1',
  'user': {
    'unique_id': by ?? 'user$id',
    'nickname': 'User $id',
    'avatar_thumb': {
      'url_list': ['https://p16/$id.jpg'],
    },
  },
};

String _answer(
  List<Map<String, dynamic>> comments, {
  bool more = false,
  int total = 0,
}) => jsonEncode({
  'status_code': 0,
  'comments': comments,
  'has_more': more ? 1 : 0,
  'total': total,
  'cursor': 20,
});

/// TikTok's video page, played by the test: it records what Toomu asks of
/// it, and the test answers as TikTok would.
class _Page implements TiktokVideoPage {
  final _out = StreamController<TiktokPageEvent>.broadcast(sync: true);
  final opened = <String>[];
  final runs = <String>[];

  /// Answers the next command with (kind, text, url), if set.
  TiktokPageEvent Function(String command)? reply;

  @override
  ValueListenable<Widget?> get page => ValueNotifier<Widget?>(null);

  @override
  Stream<TiktokPageEvent> get events => _out.stream;

  @override
  Future<void> open(String url) async => opened.add(url);

  @override
  Future<void> run(String command) async {
    runs.add(command);
    final r = reply?.call(command);
    if (r != null) scheduleMicrotask(() => _out.add(r));
  }

  @override
  Future<void> close() async {}

  void say(String kind, String text, String url) =>
      _out.add(TiktokPageEvent(kind, text, url));
}

const _ok = '{"status_code":0}';
String _likeUrl(String type) =>
    'https://www.tiktok.com/api/commit/item/digg/?aweme_id=77&type=$type';
const _commentsUrl =
    'https://www.tiktok.com/api/comment/list/?aweme_id=77&cursor=0&count=20';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('comment data', () {
    test(
      "TikTok's comments are read: author, text, likes, replies, creator's like",
      () {
        final page = TiktokCommentPage.parse(
          _answer(
            [_comment('c1', replies: 4, liked: true)],
            more: true,
            total: 120,
          ),
        )!;
        expect(page.total, 120);
        expect(page.hasMore, isTrue);
        final c = page.comments.single;
        expect(c.id, 'c1');
        expect(c.text, 'Comment c1');
        expect(c.shownName, 'User c1');
        expect(c.avatarUrl, 'https://p16/c1.jpg');
        expect(c.likes, 5);
        expect(c.liked, isTrue);
        expect(c.replyCount, 4);
        expect(c.likedByAuthor, isTrue);
        expect(c.time, DateTime.fromMillisecondsSinceEpoch(1795000000 * 1000));
      },
    );

    test(
      "a visitor's empty answer (checked in Chrome) isn't taken for 'no comments'",
      () {
        expect(TiktokCommentPage.parse(''), isNull);
        expect(TiktokCommentPage.parse('{"foo": 1}'), isNull);
        expect(
          TiktokCommentPage.parse('{"status_code": 0}')?.comments,
          isEmpty,
        );
      },
    );

    test("TikTok's short times", () {
      final now = DateTime(2026, 11, 18, 12);
      expect(
        tiktokAgo(now.subtract(const Duration(seconds: 20)), now: now),
        'Just now',
      );
      expect(
        tiktokAgo(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        tiktokAgo(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        tiktokAgo(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      expect(tiktokAgo(DateTime(2026, 1, 15), now: now), '1-15');
      expect(tiktokAgo(DateTime(2024, 1, 15), now: now), '2024-1-15');
    });
  });

  group('likes go to TikTok', () {
    late _Page page;
    late RxBool signedIn;
    late int signIns;
    late List<String> problems;
    late TiktokActions actions;

    setUp(() {
      page = _Page();
      signedIn = true.obs;
      signIns = 0;
      problems = [];
      TiktokActions.timeout = const Duration(milliseconds: 100);
      actions = TiktokActions(
        page: page,
        signedIn: signedIn,
        signIn: () async {
          signIns++;
          return false;
        },
        onProblem: (t, _) => problems.add(t),
      );
    });

    test(
      "TikTok's own like button is pressed on the video's page; the heart turns red at once",
      () async {
        page.reply = (_) => TiktokPageEvent('like', _ok, _likeUrl('1'));
        final done = actions.toggleLike(_item);
        expect(
          actions.isLiked(_item),
          isTrue,
          reason: 'red before TikTok answers',
        );
        expect(actions.likesOf(_item), 11);
        await done;
        expect(page.opened, ['https://www.tiktok.com/@maker/video/77']);
        expect(page.runs.single, contains('__toomuLike'));
        expect(actions.isLiked(_item), isTrue);
        expect(problems, isEmpty);
      },
    );

    test(
      'when TikTok had it the other way, the button is pressed once more',
      () async {
        var presses = 0;
        page.reply = (_) =>
            TiktokPageEvent('like', _ok, _likeUrl(++presses == 1 ? '0' : '1'));
        await actions.toggleLike(_item);
        expect(presses, 2);
        expect(actions.isLiked(_item), isTrue);
      },
    );

    test('TikTok refusing puts the heart back and says so', () async {
      page.reply = (_) =>
          TiktokPageEvent('like', '{"status_code":8}', _likeUrl('1'));
      await actions.toggleLike(_item);
      expect(actions.isLiked(_item), isFalse);
      expect(actions.likesOf(_item), 10);
      expect(problems, ["Couldn't like on TikTok"]);
    });

    test('no answer from TikTok puts the heart back too', () async {
      await actions.toggleLike(_item);
      expect(actions.isLiked(_item), isFalse);
      expect(problems, hasLength(1));
    });

    test("another video's like answer doesn't count", () async {
      page.reply = (_) => const TiktokPageEvent(
        'like',
        _ok,
        'https://www.tiktok.com/api/commit/item/digg/?aweme_id=1&type=1',
      );
      await actions.toggleLike(_item);
      expect(actions.isLiked(_item), isFalse);
    });

    test(
      'signed out, the heart asks to sign in first (TikTok does too)',
      () async {
        signedIn.value = false;
        await actions.toggleLike(_item);
        expect(signIns, 1);
        expect(page.runs, isEmpty);
        expect(actions.isLiked(_item), isFalse);
      },
    );

    test('a liked video (from the feed data) unlikes', () async {
      const liked = TiktokItem(
        id: '77',
        authorId: 'maker',
        playUrl: 'x',
        likes: 10,
        liked: true,
      );
      page.reply = (_) => TiktokPageEvent('like', _ok, _likeUrl('0'));
      await actions.toggleLike(liked);
      expect(actions.isLiked(liked), isFalse);
      expect(actions.likesOf(liked), 9);
    });
  });

  group('comments', () {
    late _Page page;
    late TiktokCommentsController c;

    setUp(() {
      page = _Page();
      TiktokCommentsController.timeout = const Duration(milliseconds: 100);
      c = TiktokCommentsController(item: _item, page: page, signedIn: true.obs);
      c.onStart();
    });

    tearDown(() => c.onDelete());

    test("the video's page opens its comments and they are listed", () async {
      await pumpEventQueue();
      expect(page.opened.single, _item.webUrl);
      expect(page.runs.single, contains('__toomuOpenComments'));
      page.say(
        'comments',
        _answer([_comment('c1'), _comment('c2')], more: true, total: 40),
        _commentsUrl,
      );
      expect(c.comments.map((x) => x.id), ['c1', 'c2']);
      expect(c.total.value, 40);
      expect(c.loading.value, isFalse);
    });

    test("another video's comments and repeats are left out", () async {
      page.say(
        'comments',
        _answer([_comment('x')]),
        'https://www.tiktok.com/api/comment/list/?aweme_id=1',
      );
      page.say('comments', _answer([_comment('c1')]), _commentsUrl);
      page.say(
        'comments',
        _answer([_comment('c1'), _comment('c2')]),
        _commentsUrl,
      );
      expect(c.comments.map((x) => x.id), ['c1', 'c2']);
    });

    test(
      'near the end the next comments are asked for, once until they come',
      () async {
        page.say(
          'comments',
          _answer([_comment('c1')], more: true),
          _commentsUrl,
        );
        c.more();
        c.more();
        expect(
          page.runs.where((r) => r.contains('__toomuMoreComments')),
          hasLength(1),
        );
        expect(page.runs.last, contains('"Comment c1"'));
        page.say('comments', _answer([_comment('c2')]), _commentsUrl);
        expect(c.hasMore.value, isFalse);
        c.more();
        expect(
          page.runs.where((r) => r.contains('__toomuMoreComments')),
          hasLength(1),
          reason: 'no more left',
        );
      },
    );

    test(
      'nothing from TikTok: the sheet says so (no endless spinner)',
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(c.loading.value, isFalse);
        expect(c.error.value, isNotNull);
      },
    );

    test(
      '"View replies" opens them under their comment; "Hide" closes them',
      () async {
        page.say(
          'comments',
          _answer([_comment('c1', replies: 2)]),
          _commentsUrl,
        );
        final parent = c.comments.single;
        c.toggleReplies(parent);
        expect(page.runs.last, contains('__toomuReplies'));
        expect(c.loadingReplies.contains('c1'), isTrue);
        page.say(
          'replies',
          _answer([_comment('r1'), _comment('r2')], more: false),
          'https://www.tiktok.com/api/comment/list/reply/?comment_id=c1&item_id=77',
        );
        expect(c.replies['c1']!.map((r) => r.id), ['r1', 'r2']);
        expect(c.loadingReplies.contains('c1'), isFalse);
        c.toggleReplies(parent);
        expect(c.open.contains('c1'), isFalse);
        final asked = page.runs.length;
        c.toggleReplies(parent);
        expect(
          page.runs.length,
          asked,
          reason: 'shown again without asking TikTok again',
        );
      },
    );

    test("a comment's heart goes to TikTok; a refusal puts it back", () async {
      page.say(
        'comments',
        _answer([_comment('c1'), _comment('c2')]),
        _commentsUrl,
      );
      page.reply = (cmd) => cmd.contains('"Comment c1"')
          ? const TiktokPageEvent(
              'commentLike',
              _ok,
              'https://www.tiktok.com/api/comment/digg/?cid=c1&digg_type=1',
            )
          : const TiktokPageEvent(
              'commentLike',
              '{"status_code":5}',
              'https://www.tiktok.com/api/comment/digg/?cid=c2&digg_type=1',
            );
      await c.toggleLike(c.comments[0]);
      expect(c.comments[0].liked, isTrue);
      expect(c.comments[0].likes, 6);
      await c.toggleLike(c.comments[1]);
      expect(c.comments[1].liked, isFalse);
      expect(c.comments[1].likes, 5);
    });

    test('a reply can be liked too', () async {
      page.say('comments', _answer([_comment('c1', replies: 1)]), _commentsUrl);
      c.toggleReplies(c.comments.single);
      page.say(
        'replies',
        _answer([_comment('r1')]),
        'https://www.tiktok.com/api/comment/list/reply/?comment_id=c1',
      );
      page.reply = (_) => const TiktokPageEvent(
        'commentLike',
        _ok,
        'https://www.tiktok.com/api/comment/digg/?cid=r1&digg_type=1',
      );
      await c.toggleLike(c.replies['c1']!.single, parent: 'c1');
      expect(c.replies['c1']!.single.liked, isTrue);
    });
  });

  group('comments sheet', () {
    Future<(TiktokCommentsController, _Page)> open(
      WidgetTester tester, {
      bool signedIn = true,
    }) async {
      final page = _Page();
      final c = TiktokCommentsController(
        item: _item,
        page: page,
        signedIn: signedIn.obs,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TiktokCommentsSheet(item: _item, controller: c),
            ),
          ),
        ),
      );
      await tester.pump();
      return (c, page);
    }

    testWidgets(
      "TikTok's sheet: comment count, names, the creator's tag, hearts, View replies",
      (tester) async {
        final (_, page) = await open(tester);
        page.say(
          'comments',
          _answer([
            _comment('c1', replies: 3),
            _comment('c2', by: 'maker', liked: true),
          ], total: 1234),
          _commentsUrl,
        );
        await tester.pump();
        expect(find.text('1.2K comments'), findsOneWidget);
        expect(find.text('User c1'), findsOneWidget);
        expect(find.text('Comment c1'), findsOneWidget);
        expect(
          find.text('· Creator'),
          findsOneWidget,
          reason: "the video's author",
        );
        expect(find.text('Liked by creator'), findsOneWidget);
        expect(find.text('View 3 replies'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Icon &&
                w.icon == Icons.favorite_rounded &&
                w.color == tiktokRed,
          ),
          findsWidgets,
          reason: 'c2 is liked: red heart',
        );
        await tester.tap(find.text('View 3 replies'));
        await tester.pump();
        page.say(
          'replies',
          _answer([_comment('r1')], more: true),
          'https://www.tiktok.com/api/comment/list/reply/?comment_id=c1',
        );
        await tester.pump();
        expect(find.text('Comment r1'), findsOneWidget);
        expect(find.text('View 2 more'), findsOneWidget);
        expect(find.text('Hide'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('the close button sits at the right edge, not on top of the title', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (_, page) = await open(tester);
      page.say('comments', _answer([_comment('c1')], total: 12), _commentsUrl);
      await tester.pump();
      final title = tester.getRect(find.text('12 comments'));
      final close = tester.getRect(find.byTooltip('Close'));
      final sheet = tester.getRect(find.byType(TiktokCommentsSheet));
      expect(close.overlaps(title), isFalse);
      expect(sheet.right - close.right, lessThan(16), reason: 'at the right edge');
      expect((title.center.dx - sheet.center.dx).abs(), lessThan(2), reason: 'title centred');
    });

    testWidgets(
      'signed out, the sheet asks to sign in (TikTok sends visitors no comments)',
      (tester) async {
        final (_, page) = await open(tester, signedIn: false);
        expect(find.text('Sign in to see comments'), findsOneWidget);
        expect(page.runs, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('double tap to like', () {
    late _Page page;
    late RxBool signedIn;
    late int signIns;
    late TiktokActions actions;

    setUp(() {
      page = _Page();
      signedIn = true.obs;
      signIns = 0;
      TiktokActions.timeout = const Duration(milliseconds: 100);
      actions = TiktokActions(
        page: page,
        signedIn: signedIn,
        signIn: () async {
          signIns++;
          return false;
        },
      );
    });

    test('a double tap likes the video on TikTok', () async {
      page.reply = (_) => TiktokPageEvent('like', _ok, _likeUrl('1'));
      await actions.doubleTapLike(_item);
      expect(actions.isLiked(_item), isTrue);
      expect(page.runs.single, contains('__toomuLike'));
    });

    test(
      'a double tap on a liked video never unlikes it (TikTok neither)',
      () async {
        const liked = TiktokItem(
          id: '77',
          authorId: 'maker',
          playUrl: 'x',
          likes: 10,
          liked: true,
        );
        await actions.doubleTapLike(liked);
        expect(page.runs, isEmpty);
        expect(actions.isLiked(liked), isTrue);
      },
    );

    test('signed out, a double tap asks to sign in', () async {
      signedIn.value = false;
      await actions.doubleTapLike(_item);
      expect(signIns, 1);
      expect(page.runs, isEmpty);
    });

    Finder heart() => find.byWidgetPredicate(
      (w) =>
          w is Icon && w.icon == Icons.favorite_rounded && w.color == tiktokRed,
    );

    testWidgets(
      "two quick taps: TikTok's heart bursts where the finger was, and the video is liked",
      (tester) async {
        var taps = 0, likes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TiktokTapLayer(
                onTap: () => taps++,
                onDoubleTap: () => likes++,
              ),
            ),
          ),
        );
        await tester.tapAt(const Offset(120, 300));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(120, 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(likes, 1);
        expect(taps, 0, reason: 'a double tap does not also pause');
        expect(heart(), findsOneWidget);
        final at = tester.getCenter(heart());
        expect(at.dx, closeTo(120, 1));
        await tester.pump(const Duration(seconds: 1));
        expect(heart(), findsNothing, reason: 'the heart fades away');
      },
    );

    testWidgets(
      'one tap still pauses (after a moment, to tell it from a double tap)',
      (tester) async {
        var taps = 0, likes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TiktokTapLayer(
                onTap: () => taps++,
                onDoubleTap: () => likes++,
              ),
            ),
          ),
        );
        await tester.tapAt(const Offset(120, 300));
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, 1);
        expect(likes, 0);
        expect(heart(), findsNothing);
      },
    );
  });

  test('sign-in page design: laid out at the phone\'s width, not shrunk to fit (it showed tiny and broken)', () {
    final s = TiktokSignInPage.settings();
    expect(s.useWideViewPort, isFalse, reason: 'a wide (980 px) layout squeezed onto the phone');
    expect(s.loadWithOverviewMode, isFalse, reason: 'zoomed out to fit the widest element: everything tiny');
    expect(s.supportZoom, isFalse, reason: 'pinching moved the shrunk page around');
    expect(s.userAgent, isNotEmpty, reason: 'the feed pages\' identity: the session is tied to it');
  });
}

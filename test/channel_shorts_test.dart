import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/modules/channel/controllers/channel_controller.dart';
import 'package:toomu/app/modules/shorts/controllers/shorts_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _video(String id) => Video(VideoId(id), 'Video $id', 'Cabin Builders', ChannelId('UC${'b' * 22}'), null, null,
    null, '', const Duration(minutes: 1), ThumbnailSet(id), null, const Engagement(10, null, null), false);

String _id(String s) => s.padRight(11, '_');

class _Channels implements ChannelSource {
  final asked = <String>[];
  Completer<void>? holdVideos;

  @override
  Future<Channel> channel(ChannelId id) async => Channel(id, 'Cabin Builders', '', '', 1000);

  @override
  Future<VideosPage> uploads(ChannelId id, {required bool shorts, required VideoSorting sort}) async {
    asked.add('${shorts ? 'shorts' : 'videos'}/${sort.name}');
    if (!shorts) await holdVideos?.future;
    final kind = shorts ? 's' : sort.name[0];
    return VideosPage([_video(_id('${kind}1'))], () async => VideosPage([_video(_id('${kind}2'))]));
  }
}

void main() {
  group('channel page', () {
    ChannelController open(_Channels source) => ChannelController((id: 'UC${'b' * 22}', title: 'Cabin Builders'), source);

    test('Videos (latest first) by default; Shorts and the sort orders load their own list', () async {
      final source = _Channels();
      final c = open(source);
      await c.load();
      expect(c.videos.single.id.value, _id('n1'));
      await c.sortBy(VideoSorting.popularity);
      expect(c.videos.single.id.value, _id('p1'));
      await c.showShorts(true);
      expect(c.videos.single.id.value, _id('s1'));
      expect(source.asked, ['videos/newest', 'videos/popularity', 'shorts/popularity']);
    });

    test('more videos come page by page, then stop', () async {
      final c = open(_Channels());
      await c.load();
      await c.loadMore();
      expect(c.videos.map((v) => v.id.value), [_id('n1'), _id('n2')]);
      await c.loadMore();
      expect(c.videos, hasLength(2));
    });

    test('a slow answer for the tab left behind does not replace the new one', () async {
      final source = _Channels()..holdVideos = Completer<void>();
      final c = open(source);
      final slow = c.load(); // Videos, held back
      await c.showShorts(true);
      source.holdVideos!.complete();
      await slow;
      expect(c.videos.single.id.value, _id('s1'));
      expect(c.loading.value, isFalse);
    });
  });

  group('Shorts', () {
    final shorts = [_video(_id('a')), _video(_id('b')), _video(_id('c'))];
    VideoItem item(Video v) => VideoItem(uri: 'https://x/${v.id.value}', title: v.title, remoteKey: 'yt:${v.id.value}');

    test('the short on screen is looked up and played', () async {
      final played = <String>[];
      final c = ShortsController((videos: shorts, index: 1),
          resolve: (v) async => item(v), play: (i) async => played.add(i.youtubeId!), stop: () async {});
      await c.show(1);
      expect(played.last, _id('b'));
      expect(c.playing.value, _id('b'));
      await c.show(2);
      expect(played.last, _id('c'));
    });

    test('swiping past a short quickly: only the last one plays', () async {
      final played = <String>[];
      final slow = Completer<void>();
      final c = ShortsController((videos: shorts, index: 0), resolve: (v) async {
        if (v.id.value == _id('a')) await slow.future;
        return item(v);
      }, play: (i) async => played.add(i.youtubeId!), stop: () async {});
      final first = c.show(0);
      await c.show(1);
      slow.complete();
      await first;
      expect(played, [_id('b')]);
      expect(c.playing.value, _id('b'));
    });

    test('flicking through Shorts looks up only the one it stops on, not every one passed', () async {
      // Each short swiped past started its own YouTube lookup and they all ran at once: the one on screen
      // then took 4-12 s, timed out or got only its first minute.
      ShortsController.settle = const Duration(milliseconds: 30);
      addTearDown(() => ShortsController.settle = const Duration(milliseconds: 300));
      final many = [for (final s in 'abcde'.split('')) _video(_id(s))];
      final hold = Completer<void>();
      final looked = <String>[];
      final c = ShortsController((videos: many, index: 0), resolve: (v) async {
        looked.add(v.id.value);
        if (v.id.value == _id('b')) await hold.future;
        return item(v);
      }, play: (_) async {}, stop: () async {});
      await c.show(0, now: true);
      final passed = [c.show(1), c.show(2), c.show(3)];
      await c.show(4);
      hold.complete();
      await Future.wait(passed);
      expect(looked, [_id('a'), _id('b'), _id('e')]);
      expect(c.playing.value, _id('e'));
    });

    test('Shorts play quickly: one swipe starts at once, and the next short is looked up ahead', () async {
      ShortsController.settle = const Duration(seconds: 5); // would show if a single swipe waited
      addTearDown(() => ShortsController.settle = const Duration(milliseconds: 300));
      final ahead = <String>[];
      final c = ShortsController((videos: shorts, index: 0),
          resolve: (v) async => item(v), play: (_) async {}, stop: () async {}, prefetch: (v) => ahead.add(v.id.value));
      await c.show(0, now: true);
      expect(ahead, [_id('b')]);
      await c.show(1).timeout(const Duration(seconds: 1));
      expect(c.playing.value, _id('b'));
      expect(ahead, [_id('b'), _id('c')]);
      await c.show(2);
      expect(ahead, [_id('b'), _id('c')], reason: 'nothing after the last');
    });

    test('swiping to the next short: the one before goes quiet at once, not when the next starts', () async {
      final events = <String>[];
      final hold = Completer<void>();
      final c = ShortsController((videos: shorts, index: 0), resolve: (v) async {
        if (v.id.value == _id('b')) await hold.future;
        return item(v);
      }, play: (i) async => events.add('play ${i.youtubeId}'), stop: () async {}, pause: () async => events.add('pause'));
      await c.show(0, now: true);
      final next = c.show(1);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['play ${_id('a')}', 'pause'], reason: 'quiet while b loads');
      hold.complete();
      await next;
      expect(events.last, 'play ${_id('b')}');
    });

    test('a short still opening when swiped away does not start playing over the next one', () async {
      final events = <String>[];
      final opening = Completer<void>();
      final hold = Completer<void>();
      final c = ShortsController((videos: shorts, index: 0), resolve: (v) async {
        if (v.id.value == _id('b')) await hold.future;
        return item(v);
      }, play: (i) async {
        events.add('play ${i.youtubeId}');
        if (i.youtubeId == _id('a')) await opening.future;
      }, stop: () async {}, pause: () async => events.add('pause'));
      final first = c.show(0, now: true);
      await Future<void>.delayed(Duration.zero);
      final next = c.show(1);
      opening.complete(); // a finishes opening (and starts) after the swipe
      await first;
      expect(events.last, 'pause');
      hold.complete();
      await next;
      expect(events.last, 'play ${_id('b')}');
    });

    test('a short that will not play says why; Try again plays it', () async {
      var fail = true;
      final c = ShortsController((videos: shorts, index: 0), resolve: (v) async {
        if (fail) throw StateError('No playable stream found for this video.');
        return item(v);
      }, play: (_) async {}, stop: () async {});
      await c.show(0);
      expect(c.error.value, isNotNull);
      expect(c.playing.value, isNull);
      fail = false;
      await c.show(0);
      expect(c.error.value, isNull);
      expect(c.playing.value, _id('a'));
    });

    test('leaving the Shorts stops the player', () async {
      var stopped = false;
      final c = ShortsController((videos: shorts, index: 0),
          resolve: (v) async => item(v), play: (_) async {}, stop: () async => stopped = true);
      c.onClose();
      expect(stopped, isTrue);
    });
  });
}

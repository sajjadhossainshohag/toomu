import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/tiktok_item.dart';
import 'package:toomu/app/modules/tiktok/tiktok_head_server.dart';
import 'package:toomu/app/modules/tiktok/tiktok_playback.dart';
import 'package:toomu/app/modules/tiktok/tiktok_prefetch.dart';

// No TestWidgetsFlutterBinding here: it would turn every HTTP request into a 400.
void main() {
  late HttpServer server;
  late Directory dir;
  late TiktokPrefetch prefetch;
  final requests = <String>[];
  final referers = <String?>[];
  final ranges = <String?>[];

  /// The fake TikTok's files: [size] bytes, answering ranges like TikTok's CDN.
  List<int> body(String id) => List<int>.generate(
    id.startsWith('short') ? 300 : 3000,
    (i) => (i * 7 + id.length) % 251,
  );

  TiktokItem video(
    String id, {
    Duration duration = const Duration(seconds: 30),
  }) => TiktokItem(
    id: id,
    authorId: 'a',
    playUrl: 'http://127.0.0.1:${server.port}/$id',
    duration: duration,
  );

  setUp(() async {
    requests.clear();
    referers.clear();
    ranges.clear();
    TiktokPrefetch.headMin = 100;
    TiktokPrefetch.headMax = 2000;
    dir = await Directory.systemTemp.createTemp('tiktok_prefetch');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final id = req.uri.pathSegments.last;
      requests.add(id);
      referers.add(req.headers.value('referer'));
      final range = req.headers.value('range');
      ranges.add(range);
      final res = req.response;
      if (id == 'forbidden') {
        res.statusCode = 403;
      } else if (id == 'nolength') {
        res.add(
          List.filled(1000, 1),
        ); // no length, no range support: size unknown
      } else {
        final all = body(id);
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
        if (m == null) {
          res.contentLength = all.length;
          res.add(all);
        } else {
          final from = int.parse(m[1]!);
          final to = m[2]!.isEmpty
              ? all.length - 1
              : int.parse(m[2]!).clamp(0, all.length - 1);
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $from-$to/${all.length}');
          res.contentLength = to - from + 1;
          res.add(all.sublist(from, to + 1));
        }
      }
      await res.close();
    });
    prefetch = TiktokPrefetch(
      folder: () async => dir,
      headers: () async => {'Referer': 'https://www.tiktok.com/'},
    );
  });

  tearDown(() async {
    TiktokPrefetch.headMin = TiktokPrefetch.defaultHeadMin;
    TiktokPrefetch.headMax = TiktokPrefetch.defaultHeadMax;
    await server.close(force: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test(
    "only the first seconds of the next videos download, in order, with a range and TikTok's headers",
    () async {
      prefetch.want([video('2'), video('3')]);
      await prefetch.idle();
      expect(requests, ['2', '3']);
      expect(referers, everyElement('https://www.tiktok.com/'));
      expect(ranges, everyElement('bytes=0-${TiktokPrefetch.headMax - 1}'));
      final head = prefetch.headFor('2')!;
      // 3000 bytes over 30 s: 4 s is 400 bytes.
      expect(head.length, 400);
      expect(head.total, 3000);
      expect(head.complete, isFalse);
      expect(File(head.path).readAsBytesSync(), body('2').sublist(0, 400));
    },
  );

  test('a short video comes whole', () async {
    prefetch.want([video('short1', duration: const Duration(seconds: 2))]);
    await prefetch.idle();
    final head = prefetch.headFor('short1')!;
    expect(head.length, 300);
    expect(head.complete, isTrue);
  });

  test('a video already downloaded ahead is not fetched again', () async {
    prefetch.want([video('2')]);
    await prefetch.idle();
    prefetch.want([video('2'), video('3')]);
    await prefetch.idle();
    expect(requests, ['2', '3']);
  });

  test(
    'a refused download, or one of unknown size, leaves no file behind',
    () async {
      prefetch.want([video('forbidden'), video('nolength')]);
      await prefetch.idle();
      expect(prefetch.headFor('forbidden'), isNull);
      expect(prefetch.headFor('nolength'), isNull);
      expect(dir.listSync(), isEmpty);
    },
  );

  test('a video too big for a reel is left to stream', () async {
    final max = TiktokPrefetch.maxBytes;
    TiktokPrefetch.maxBytes = 1000;
    addTearDown(() => TiktokPrefetch.maxBytes = max);
    prefetch.want([video('2')]);
    await prefetch.idle();
    expect(prefetch.headFor('2'), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('only the last few heads stay on disk', () async {
    for (var i = 0; i < TiktokPrefetch.keep + 4; i++) {
      prefetch.want([video('$i')]);
      await prefetch.idle();
    }
    expect(dir.listSync().length, TiktokPrefetch.keep);
    expect(prefetch.headFor('0'), isNull);
    expect(prefetch.headFor('${TiktokPrefetch.keep + 3}'), isNotNull);
  });

  test('clearing deletes every downloaded head', () async {
    prefetch.want([video('2'), video('3')]);
    await prefetch.idle();
    await prefetch.clear();
    expect(prefetch.headFor('2'), isNull);
    expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
  });

  group('the head server', () {
    late TiktokHeadServer heads;

    setUp(() async {
      heads = TiktokHeadServer(
        headers: () async => {'Referer': 'https://www.tiktok.com/'},
      );
      prefetch.want([video('2')]);
      await prefetch.idle();
      requests.clear();
      ranges.clear();
      referers.clear();
    });

    tearDown(() => heads.close());

    Future<(HttpClientResponse, List<int>)> get(
      String url, {
      String? range,
    }) async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(Uri.parse(url));
      if (range != null) req.headers.set('range', range);
      final res = await req.close();
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      return (res, bytes);
    }

    test(
      'plays on past the head: the first seconds from the file, the rest from TikTok',
      () async {
        final url = (await heads.urlFor(video('2'), prefetch.headFor('2')!))!;
        expect(url, startsWith('http://127.0.0.1:'));
        final (res, bytes) = await get(url, range: 'bytes=0-');
        expect(res.statusCode, 206);
        expect(res.headers.value('content-range'), 'bytes 0-2999/3000');
        expect(res.headers.value('accept-ranges'), 'bytes');
        expect(res.headers.contentType?.mimeType, 'video/mp4');
        expect(bytes, body('2'));
        expect(ranges, [
          'bytes=400-2999',
        ], reason: 'only what the head lacks comes from TikTok');
        expect(referers, ['https://www.tiktok.com/']);
      },
    );

    test('a range inside the head is served from the file alone', () async {
      final url = (await heads.urlFor(video('2'), prefetch.headFor('2')!))!;
      final (res, bytes) = await get(url, range: 'bytes=100-199');
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 100-199/3000');
      expect(bytes, body('2').sublist(100, 200));
      expect(requests, isEmpty);
    });

    test('a range past the head (a seek) goes straight to TikTok', () async {
      final url = (await heads.urlFor(video('2'), prefetch.headFor('2')!))!;
      final (res, bytes) = await get(url, range: 'bytes=1000-1499');
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 1000-1499/3000');
      expect(bytes, body('2').sublist(1000, 1500));
      expect(ranges, ['bytes=1000-1499']);
    });

    test('no range: the whole video, head first', () async {
      final url = (await heads.urlFor(video('2'), prefetch.headFor('2')!))!;
      final (res, bytes) = await get(url);
      expect(res.statusCode, 200);
      expect(res.contentLength, 3000);
      expect(bytes, body('2'));
    });

    test('a head deleted meanwhile: everything from TikTok', () async {
      final head = prefetch.headFor('2')!;
      final url = (await heads.urlFor(video('2'), head))!;
      File(head.path).deleteSync();
      final (res, bytes) = await get(url, range: 'bytes=0-');
      expect(res.statusCode, 206);
      expect(bytes, body('2'));
      expect(ranges, ['bytes=0-2999']);
    });

    test('an unknown video is not found', () async {
      final url = (await heads.urlFor(video('2'), prefetch.headFor('2')!))!;
      final (res, _) = await get(url.replaceFirst('/2.mp4', '/nope.mp4'));
      expect(res.statusCode, 404);
    });
  });

  test(
    'a video with a head plays through the head server; others straight from TikTok',
    () {
      final item = TiktokItem(
        id: '7',
        authorId: 'a',
        playUrl: 'https://v16.tiktok.com/7.mp4',
      );
      final local = SessionTiktokPlayback.videoFor(
        item,
        local: 'http://127.0.0.1:5000/tt/7.mp4',
        headers: const {'Referer': 'r'},
      );
      expect(local.playable, 'http://127.0.0.1:5000/tt/7.mp4');
      expect(local.path, isNull);
      expect(
        local.httpHeaders,
        isEmpty,
        reason: "the server adds TikTok's headers itself",
      );
      final remote = SessionTiktokPlayback.videoFor(
        item,
        headers: const {'Referer': 'r'},
      );
      expect(remote.playable, 'https://v16.tiktok.com/7.mp4');
      expect(remote.httpHeaders, {'Referer': 'r'});
      expect(local.remoteKey, remote.remoteKey);
    },
  );

  group('a video counts as started', () {
    test(
      'no time runs while the video loads: started = loading ended, not a leftover position',
      () async {
        final buffering = StreamController<bool>.broadcast(sync: true);
        var done = false;
        final started = SessionTiktokPlayback.started(
          buffering.stream,
          () async {
            buffering.add(
              false,
            ); // the previous video's state, before the new file begins
          },
        ).then((_) => done = true);
        await pumpEventQueue();
        expect(done, isFalse, reason: 'the new video has not begun loading');
        buffering.add(true); // mpv starts the file
        await pumpEventQueue();
        expect(done, isFalse, reason: 'still loading');
        buffering.add(false); // playing
        await started;
        expect(done, isTrue);
        await buffering.close();
      },
    );

    test('a preloaded video starts at once: its first frame counts even when mpv never says loading ended', () async {
      // Swiping from a playing video to a fast one, mpv's idle flag goes on
      // and off before media_kit sees it: no "loading ended" ever came, and
      // the spinner stayed up for the whole timeout over a ready video.
      final buffering = StreamController<bool>.broadcast(sync: true);
      final position = StreamController<Duration>.broadcast(sync: true);
      var done = false;
      final started = SessionTiktokPlayback.started(
        buffering.stream,
        () async => position.add(const Duration(seconds: 7)), // the old video's time
        position: position.stream,
        timeout: const Duration(seconds: 3),
      ).then((_) => done = true);
      final sw = Stopwatch()..start();
      await pumpEventQueue();
      expect(done, isFalse, reason: "the old video's position doesn't count");
      buffering.add(true); // mpv starts the new file
      position.add(Duration.zero);
      await pumpEventQueue();
      expect(done, isFalse, reason: 'not playing yet');
      position.add(const Duration(milliseconds: 40)); // its first frame
      await started;
      expect(done, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'at its first frame, not after the timeout');
      await buffering.close();
      await position.close();
    });

    test('a video that never reports gives up waiting after a while', () async {
      final buffering = StreamController<bool>.broadcast();
      final sw = Stopwatch()..start();
      await SessionTiktokPlayback.started(
        buffering.stream,
        () async {},
        timeout: const Duration(milliseconds: 50),
      );
      expect(sw.elapsedMilliseconds, lessThan(1000));
      await buffering.close();
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/models/media_format.dart';
import 'package:toomu/app/data/models/tiktok_item.dart';
import 'package:toomu/app/services/download_service.dart';

import 'support/download_harness.dart';

/// TikTok and other sites' streams (yt-dlp on the link), and links that expire.
void main() {
  late DownloadHarness h;

  setUp(() async {
    h = DownloadHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  DownloadService s() => DownloadService.to;
  List<YtDlpCall> calls() => h.ytdlp.calls;

  // Unreachable on purpose: the subtitle check of a stream fails fast and quietly.
  const stream = 'http://127.0.0.1:9/live/master.m3u8';

  group('TikTok', () {
    test('downloads from its page with a browser identity, named after the author and caption', () async {
      final t = await s().enqueueTiktok(const TiktokItem(id: '7301', authorId: 'dancer', caption: 'New moves'));
      await DownloadHarness.status(t, DownloadStatus.completed);
      final c = calls().single;
      expect(c.kind, 'url');
      expect(c.url, 'https://www.tiktok.com/@dancer/video/7301');
      expect(c.args, contains('--user-agent'));
      expect(c.option('-f'), 'b[vcodec^=h264]/b[vcodec^=avc]/b');
      expect(t.filePath, '${h.root}/Video/@dancer - New moves.mp4');
    });

    test('a TikTok saved as MP3 goes to Audio, converted like YouTube audio', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.ok(c, ext: 'mp3');
      final t = await s().enqueueTiktok(
        const TiktokItem(id: '7303', authorId: 'singer', caption: 'Song'),
        format: MediaFormat.tiktokOptions.firstWhere((f) => f.extension == 'mp3'),
      );
      await DownloadHarness.status(t, DownloadStatus.completed);
      final c = calls().single;
      expect(c.url, 'https://www.tiktok.com/@singer/video/7303');
      expect(c.args, contains('--user-agent'));
      expect(c.option('-f'), 'ba/b');
      expect(c.args, containsAllInOrder(['-x', '--audio-format', 'mp3']));
      expect(t.kind, DownloadKind.audio);
      expect(t.filePath, '${h.root}/Audio/@singer - Song.mp3');
    });

    test('a TikTok saved as original audio is an M4A in Audio', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.ok(c, ext: 'm4a');
      final t = await s().enqueueTiktok(
        const TiktokItem(id: '7304', authorId: 'singer', caption: 'Song'),
        format: MediaFormat.tiktokOptions.firstWhere((f) => f.extension == 'm4a'),
      );
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls().single.args, containsAllInOrder(['-x', '--audio-format', 'm4a']));
      expect(t.filePath, '${h.root}/Audio/@singer - Song.m4a');
    });

    test('TikTok offers video, MP3 and original audio', () {
      expect(MediaFormat.tiktokOptions.map((f) => (f.kind, f.extension)), [
        (DownloadKind.video, 'mp4'),
        (DownloadKind.audio, 'mp3'),
        (DownloadKind.audio, 'm4a'),
      ]);
    });

    test('no caption: named after the video id', () async {
      final t = await s().enqueueTiktok(const TiktokItem(id: '7302', authorId: 'quiet'));
      expect(t.title, 'TikTok 7302');
    });
  });

  group('streams from other sites', () {
    Future<DownloadTask> enqueue({Map<String, String> headers = const {}, String? pageUrl}) => s().enqueueStream(
      url: stream,
      title: 'Episode 1',
      format: 'best',
      qualityLabel: '720p',
      headers: headers,
      pageUrl: pageUrl,
    );

    test('segments in parallel, with the page\'s headers', () async {
      final t = await enqueue(headers: {'Referer': 'https://site.example/watch', 'Origin': 'https://site.example'});
      await DownloadHarness.status(t, DownloadStatus.completed);
      final c = calls().first;
      expect(c.url, stream);
      expect(c.option('--concurrent-fragments'), '4');
      expect(c.option('--referer'), 'https://site.example/watch');
      expect(c.option('--add-header'), 'Origin:https://site.example');
      expect(t.filePath, '${h.root}/Video/Episode 1 (720p).mp4');
    });

    test('a site that refuses many requests at once gets the same download one segment at a time, from scratch', () async {
      var leftover = '';
      h.ytdlp.onRun = (c, _, _) async {
        if (c.option('--concurrent-fragments') != null && c.args.contains('--write-subs') == false) {
          File('${c.path('temp')}/Frag1.part').writeAsBytesSync([1]);
          return FakeYtDlp.failed('ERROR: HTTP Error 429: Too Many Requests');
        }
        leftover = Directory(c.path('temp')).listSync().map((e) => e.path).join(',');
        return FakeYtDlp.ok(c);
      };
      final t = await enqueue();
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls().map((c) => c.option('--concurrent-fragments')), ['4', null]);
      expect(leftover, isNot(contains('Frag1')));
    });

    test('a full phone is not retried one segment at a time', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.failed('ERROR: [Errno 28] No space left on device');
      final t = await enqueue();
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(calls(), hasLength(1));
      expect(t.error.value, contains('Not enough free storage'));
    });

    test('a stream link that stopped working says "Refresh link"', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.failed('ERROR: unable to download video data: HTTP Error 403: Forbidden');
      final t = await enqueue(pageUrl: 'https://site.example/watch');
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, DownloadService.linkExpiredText);
    });

    test('pausing a stream stops yt-dlp', () async {
      h.ytdlp.onRun = (c, _, canceled) async {
        await canceled;
        return FakeYtDlp.failed('killed');
      };
      final t = await enqueue();
      await DownloadHarness.until(() => calls().isNotEmpty, what: 'yt-dlp to start');
      s().pause(t);
      await DownloadHarness.status(t, DownloadStatus.paused);
      expect(h.ytdlp.canceledIds, contains(t.id));
    });
  });

  group('expired links of browser downloads', () {
    late FileServer origin;
    const size = 2 * 1024 * 1024 + 7;

    setUp(() async {
      origin = FileServer(size);
      await origin.start();
    });
    tearDown(() => origin.stop());

    test('a link from a page that now answers 403 says "Refresh link"', () async {
      origin.status = 403;
      final t = await s().enqueueDirect(url: origin.url.toString(), pageUrl: 'https://site.example/file');
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, DownloadService.linkExpiredText);
    });

    test('without a page to refresh from, the error is shown as it is', () async {
      origin.status = 403;
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, isNot(DownloadService.linkExpiredText));
    });

    Future<DownloadTask> pausedHalfway() async {
      origin.bytesPerSecond = 150 * 1024;
      final t = await s().enqueueDirect(url: origin.url.toString(), pageUrl: 'https://site.example/file');
      await DownloadHarness.until(() => t.receivedBytes.value > 0, what: 'some bytes');
      s().pause(t);
      await DownloadHarness.status(t, DownloadStatus.paused);
      origin.bytesPerSecond = null;
      return t;
    }

    test('a refreshed link to the same file keeps the bytes already saved and finishes', () async {
      final t = await pausedHalfway();
      final kept = t.receivedBytes.value;
      origin.requests = 0;
      await s().replaceLink(t, '${origin.url}?fresh=1', const {'Referer': 'https://site.example/file'}, size: size);
      expect(t.receivedBytes.value, kept);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(t.url, '${origin.url}?fresh=1');
      expect(File(t.filePath).lengthSync(), size);
    });

    test('a refreshed link to a different size starts over (the old bytes belong to another file)', () async {
      final t = await pausedHalfway();
      await s().replaceLink(t, '${origin.url}?other=1', const {}, size: size + 1);
      expect(t.receivedBytes.value, 0);
      expect(File(t.partPath).existsSync(), isFalse);
      s().pause(t);
    });
  });
}

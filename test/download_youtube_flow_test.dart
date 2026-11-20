import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/models/media_format.dart';
import 'package:toomu/app/data/models/video_meta.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/settings_service.dart';

import 'support/download_harness.dart';

/// A YouTube download from start to file, with yt-dlp faked: which links and downloader are tried, in which
/// order, and what the user sees when each step fails.
void main() {
  late DownloadHarness h;
  const id = 'dQw4w9WgXcQ';
  const watchUrl = 'https://www.youtube.com/watch?v=$id';
  final fastJson = jsonEncode({'id': id, 'title': 'Fast', 'formats': <Object>[]});
  final lookedUpJson = jsonEncode({'id': id, 'title': 'Looked up', 'formats': <Object>[]});

  setUp(() async {
    h = DownloadHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  DownloadService s() => DownloadService.to;
  List<YtDlpCall> calls() => h.ytdlp.calls;

  const video = VideoMeta(id: id, title: 'Never Gonna Give You Up', author: 'Rick', thumbnailUrl: '');
  const hd = MediaFormat(
    kind: DownloadKind.video,
    label: '720p',
    extension: 'mp4',
    sizeBytes: 5000,
    detail: '',
    selector: '136+140',
  );

  Future<DownloadTask> download({MediaFormat format = hd, String? fast}) {
    DownloadService.fastInfoJson = (_) async => fast;
    return s().enqueue(video: video, format: format);
  }

  String workOf(DownloadTask t) => '${h.ytdlp.workRoot}/${t.id}';

  group('links in hand first', () {
    test('fast links: one run from the saved info, with aria2c and the chosen format; no lookup', () async {
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls(), hasLength(1));
      final c = calls().single;
      expect(c.kind, 'withoutUrl');
      expect(c.args, contains('--toomu-aria2c=4'));
      expect(c.option('-f'), '136+140');
      expect(c.option('--merge-output-format'), 'mp4');
      final info = c.option('--load-info-json')!;
      expect(info, '${workOf(t)}/info.json');
      expect(h.ytdlp.lookups, 0);
      expect(t.filePath, '${h.root}/Video/Never Gonna Give You Up (720p).mp4');
      expect(File(t.filePath).existsSync(), isTrue);
      expect(Directory(workOf(t)).existsSync(), isFalse, reason: 'the work folder goes once the file is done');
    });

    test('one connection chosen: the built-in downloader, no aria2c', () async {
      Get.find<SettingsService>().connectionsPerDownload.value = 1;
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls().single.aria2c, isFalse);
    });

    test('aria2c refused: the built-in downloader tries the same links, starting clean', () async {
      var leftover = '';
      h.ytdlp.onRun = (c, _, _) async {
        if (c.aria2c) {
          File('${c.path('temp')}/half.part').writeAsBytesSync([1, 2, 3]);
          return FakeYtDlp.failed('ERROR: aria2c exited with code 22');
        }
        leftover = Directory(c.path('temp')).listSync().map((e) => e.uri.pathSegments.last).join(',');
        return FakeYtDlp.ok(c);
      };
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls().map((c) => (c.kind, c.aria2c)), [('withoutUrl', true), ('withoutUrl', false)]);
      expect(leftover, isNot(contains('half.part')), reason: "aria2c's partial file can't be resumed by another downloader");
    });

    test("fast links that fail: yt-dlp's own lookup, then its links", () async {
      h.ytdlp.infoJson = lookedUpJson;
      h.ytdlp.onRun = (c, _, _) async {
        final info = File(c.option('--load-info-json')!).readAsStringSync();
        return info.contains('Looked up') ? FakeYtDlp.ok(c) : FakeYtDlp.failed('ERROR: HTTP Error 403: Forbidden');
      };
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(h.ytdlp.lookups, 1);
      expect(calls().where((c) => c.kind == 'withoutUrl'), hasLength(3), reason: 'fast: aria2c + built-in; looked up: aria2c');
      expect(calls().any((c) => c.kind == 'fallback'), isFalse);
    });

    test('no fast links: waits for the lookup and downloads from it', () async {
      h.ytdlp.infoJson = lookedUpJson;
      final t = await download();
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(h.ytdlp.lookups, 1);
      expect(File(calls().single.option('--load-info-json')!).existsSync(), isFalse, reason: 'work folder cleaned');
      expect(calls().single.kind, 'withoutUrl');
    });
  });

  group('last resort: a fresh extraction with other YouTube clients', () {
    test('no links at all: the watch page with the client fallback and the built-in downloader', () async {
      final t = await download();
      await DownloadHarness.status(t, DownloadStatus.completed);
      final c = calls().single;
      expect(c.kind, 'fallback');
      expect(c.url, watchUrl);
      expect(c.aria2c, isFalse, reason: "aria2c's large ranges straight to YouTube get refused");
    });

    test('every saved link failing ends there too', () async {
      h.ytdlp.onRun = (c, _, _) async =>
          c.kind == 'fallback' ? FakeYtDlp.ok(c) : FakeYtDlp.failed('ERROR: HTTP Error 403: Forbidden');
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(calls().last.kind, 'fallback');
    });

    test('when that fails too, the download fails with yt-dlp\'s reason', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.failed('WARNING: x\nERROR: [youtube] $id: Video unavailable');
      final t = await download();
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, contains('Video unavailable'));
    });
  });

  group('stops without retrying', () {
    test('a full phone: one run, then "Not enough free storage", no other links or clients', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.failed('ERROR: unable to write data: [Errno 28] No space left on device');
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(calls(), hasLength(1));
      expect(t.error.value, contains('Not enough free storage'));
    });

    test('a lost connection: "Connection lost", waiting to resume by itself', () async {
      h.ytdlp.onRun = (c, _, _) async =>
          FakeYtDlp.failed('ERROR: unable to download video data: <urlopen error [Errno 101] Network is unreachable>');
      final t = await download();
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, DownloadService.networkWaitText);
    });
  });

  group('pause', () {
    test('pausing mid-download stops yt-dlp (and its aria2c) and tries nothing else', () async {
      h.ytdlp.onRun = (c, progress, canceled) async {
        progress('[download] Destination: ${c.path('temp')}/x.f136.mp4');
        progress('[#2089b0 1.0MiB/4.0MiB(25%) CN:4 DL:1.0MiB ETA:3s]');
        await canceled;
        return FakeYtDlp.failed('killed');
      };
      final t = await download(fast: fastJson);
      await DownloadHarness.until(() => t.receivedBytes.value == 1024 * 1024, what: 'progress');
      s().pause(t);
      await DownloadHarness.status(t, DownloadStatus.paused);
      expect(h.ytdlp.canceledIds, contains(t.id));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls(), hasLength(1));
    });

    test('resumed after the video part finished: the live size counts it (it jumped up on pause before)', () async {
      const mib = 1024 * 1024;
      h.ytdlp.onRun = (c, progress, canceled) async {
        progress('[download] ${c.path('temp')}/x.f136.mp4 has already been downloaded');
        progress('[toomu] 136 NA ${100 * mib} NA NA finished');
        progress('[download] Destination: ${c.path('temp')}/x.f140.m4a');
        progress('[#a1b2c3 2.0MiB/4.0MiB(50%) CN:4 DL:1.0MiB ETA:2s]');
        await canceled;
        return FakeYtDlp.failed('killed');
      };
      final t = await download(fast: fastJson);
      await DownloadHarness.until(() => t.receivedBytes.value > 0, what: 'progress');
      expect(t.receivedBytes.value, 102 * mib);
      expect(t.phase.value, DownloadPhase.audio);
    });
  });

  group('the finished file', () {
    test('yt-dlp chose another container (WebM): that file is the download', () async {
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.ok(c, ext: 'webm');
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(t.filePath, endsWith('Never Gonna Give You Up (720p).webm'));
    });

    test('yt-dlp says done but there is no file: failed, not "completed" with nothing to play', () async {
      h.ytdlp.onRun = (c, _, _) async => const YtDlpResult(exitCode: 0, out: '', err: '');
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.failed);
      expect(t.error.value, contains('missing'));
    });

    test('MP3: converted at the chosen bitrate, into the audio folder; no subtitles', () async {
      var subtitles = 0;
      DownloadService.saveSubtitles = (_) async => subtitles++;
      h.ytdlp.onRun = (c, _, _) async => FakeYtDlp.ok(c, ext: 'mp3');
      const mp3 = MediaFormat(
        kind: DownloadKind.audio,
        label: 'MP3 192 kbps',
        extension: 'mp3',
        sizeBytes: 3000,
        detail: '',
        selector: 'ba',
        convert: 'mp3:192',
      );
      final t = await download(format: mp3, fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      final c = calls().single;
      expect(c.option('--audio-format'), 'mp3');
      expect(c.option('--audio-quality'), '192K');
      expect(c.args, contains('-x'));
      expect(t.filePath, startsWith('${h.root}/Audio/'));
      expect(subtitles, 0);
    });

    test('a video gets its subtitles saved', () async {
      final got = <String>[];
      DownloadService.saveSubtitles = (t) async => got.add(t.videoId);
      final t = await download(fast: fastJson);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(got, [id]);
    });
  });

  test('a whole playlist is queued once per video and downloads within the limit', () async {
    h.ytdlp.onRun = (c, _, canceled) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return FakeYtDlp.ok(c);
    };
    DownloadService.fastInfoJson = (_) async => fastJson;
    final videos = [for (final v in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']) VideoMeta(id: v, title: v, author: '', thumbnailUrl: '')];
    expect(await s().enqueueAll(videos, hd), 3);
    expect(s().tasks.where((t) => t.status.value == DownloadStatus.running), hasLength(2));
    for (final t in s().tasks.toList()) {
      await DownloadHarness.status(t, DownloadStatus.completed);
    }
    expect(await s().enqueueAll(videos, hd), 0, reason: 'already downloaded');
  });
}

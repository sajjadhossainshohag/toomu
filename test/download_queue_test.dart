import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/core/utils/subtitles.dart';
import 'package:toomu/app/core/values/app_constants.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/settings_service.dart';

import 'support/download_harness.dart';

/// The download list as the user drives it: start, queue, pause, resume, delete, restart.
void main() {
  late DownloadHarness h;
  late FileServer origin;
  const size = 3 * 1024 * 1024 + 123;

  setUp(() async {
    h = DownloadHarness();
    await h.setUp();
    origin = FileServer(size);
    await origin.start();
  });
  tearDown(() async {
    await h.tearDown();
    await origin.stop();
  });

  DownloadService s() => DownloadService.to;

  void expectWholeFile(DownloadTask t) {
    final bytes = File(t.filePath).readAsBytesSync();
    expect(bytes.length, size);
    for (var i = 0; i < size; i += 4099) {
      if (bytes[i] != byteAt(i)) fail('wrong byte at $i');
    }
  }

  Future<DownloadTask> slow({String name = 'movie.mp4'}) {
    origin.bytesPerSecond = 150 * 1024; // per connection: about 5 s for the file
    return s().enqueueDirect(url: '${origin.url}?n=$name', fileName: name);
  }

  Future<void> someBytes(DownloadTask t) =>
      DownloadHarness.until(() => t.receivedBytes.value > 0, what: '${t.title} to get some bytes');

  group('one download', () {
    test('a link downloads to a whole file in the videos folder, marked complete and sent to the gallery', () async {
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(t.filePath, '${h.root}/Video/movie.mp4');
      expectWholeFile(t);
      expect(File(t.partPath).existsSync(), isFalse);
      expect(t.receivedBytes.value, size);
      expect(h.scanned, contains(t.filePath));
      expect(h.notifications.map((c) => c.method), contains('finished'));
    });

    test('a link the server refuses ends as failed with the reason, not stuck as running', () async {
      origin.status = 400;
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.failed, limit: const Duration(seconds: 5));
      expect(t.error.value, isNotNull);
    });

    test('a second download of the same name gets "(1)", not the first one overwritten', () async {
      final a = await s().enqueueDirect(url: origin.url.toString());
      final b = await s().enqueueDirect(url: origin.url.toString());
      expect(b.filePath, '${h.root}/Video/movie (1).mp4');
      await DownloadHarness.status(a, DownloadStatus.completed);
      await DownloadHarness.status(b, DownloadStatus.completed);
    });
  });

  group('pause and resume', () {
    test('pause stops at once: no more requests, the bytes so far kept; resume finishes the same file', () async {
      final t = await slow();
      await someBytes(t);
      s().pause(t);
      await DownloadHarness.status(t, DownloadStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final requests = origin.requests;
      final kept = t.receivedBytes.value;
      expect(kept, inInclusiveRange(1, size - 1));
      expect(File(t.partPath).existsSync(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(origin.requests, requests, reason: 'nothing is fetched while paused');

      origin.bytesPerSecond = null;
      s().resume(t);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expectWholeFile(t);
    });

    test('pausing a download still waiting in the queue keeps it from starting', () async {
      Get.find<SettingsService>().maxConcurrentDownloads.value = 1;
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      expect(b.status.value, DownloadStatus.queued);
      s().pause(b);
      expect(b.status.value, DownloadStatus.paused);
      origin.bytesPerSecond = null;
      await DownloadHarness.status(a, DownloadStatus.completed);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(b.status.value, DownloadStatus.paused);
    });

    test('pause all and resume all', () async {
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      await someBytes(a);
      s().pauseAll();
      await DownloadHarness.status(a, DownloadStatus.paused);
      await DownloadHarness.status(b, DownloadStatus.paused);
      expect(s().hasActiveDownloads, isFalse);
      origin.bytesPerSecond = null;
      s().resumeAll();
      await DownloadHarness.status(a, DownloadStatus.completed);
      await DownloadHarness.status(b, DownloadStatus.completed);
    });

    test('a failed download can be resumed', () async {
      origin.status = 500;
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.failed);
      origin.status = null;
      s().resume(t);
      await DownloadHarness.status(t, DownloadStatus.completed);
      expect(t.error.value, isNull);
      expectWholeFile(t);
    });
  });

  group('queue', () {
    test('no more than the chosen number run at once; the next starts when one ends', () async {
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      final c = await slow(name: 'c.mp4');
      expect([a, b, c].map((t) => t.status.value), [DownloadStatus.running, DownloadStatus.running, DownloadStatus.queued]);
      s().pause(a);
      await DownloadHarness.status(c, DownloadStatus.running);
      expect(b.status.value, DownloadStatus.running);
    });

    test('allowing more downloads at once starts the waiting ones', () async {
      await slow(name: 'a.mp4');
      await slow(name: 'b.mp4');
      final c = await slow(name: 'c.mp4');
      expect(c.status.value, DownloadStatus.queued);
      Get.find<SettingsService>().maxConcurrentDownloads.value = 3;
      await DownloadHarness.status(c, DownloadStatus.running);
    });

    test('the oldest waiting download starts first', () async {
      Get.find<SettingsService>().maxConcurrentDownloads.value = 1;
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      final c = await slow(name: 'c.mp4');
      s().pause(a);
      await DownloadHarness.status(b, DownloadStatus.running);
      expect(c.status.value, DownloadStatus.queued);
    });
  });

  group('delete', () {
    test('deleting a running download stops it and removes its partial data for good (no .chunks folder left); the next one starts', () async {
      Get.find<SettingsService>().maxConcurrentDownloads.value = 1;
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      await someBytes(a);
      await s().remove(a);
      expect(s().tasks, isNot(contains(a)));
      expect(a.status.value, DownloadStatus.canceled);
      await DownloadHarness.status(b, DownloadStatus.running);
      // Long enough for a connection that was still closing to have written its progress file.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(File(a.partPath).existsSync(), isFalse);
      expect(Directory(DownloadTask.chunksDirOf(a.partPath)).existsSync(), isFalse);
      expect(File(a.filePath).existsSync(), isFalse);
    });

    test('deleting a finished download keeps the file unless asked; with the file go its subtitles', () async {
      final kept = await s().enqueueDirect(url: origin.url.toString(), fileName: 'kept.mp4');
      final gone = await s().enqueueDirect(url: origin.url.toString(), fileName: 'gone.mp4');
      await DownloadHarness.status(kept, DownloadStatus.completed);
      await DownloadHarness.status(gone, DownloadStatus.completed);
      final subs = Subtitles.sidecarPath(gone.filePath, 'en', 'vtt');
      File(subs).writeAsStringSync('WEBVTT');

      await s().remove(kept);
      expect(File(kept.filePath).existsSync(), isTrue);
      final freed = await s().remove(gone, deleteFile: true);
      expect(File(gone.filePath).existsSync(), isFalse);
      expect(File(subs).existsSync(), isFalse);
      expect(freed, greaterThanOrEqualTo(size));
      expect(s().tasks, isEmpty);
    });

    test('clear finished removes only finished rows', () async {
      final done = await s().enqueueDirect(url: origin.url.toString(), fileName: 'done.mp4');
      await DownloadHarness.status(done, DownloadStatus.completed);
      final waiting = await slow(name: 'waiting.mp4');
      s().pause(waiting);
      await DownloadHarness.status(waiting, DownloadStatus.paused);
      await s().clearCompleted();
      expect(s().tasks, [waiting]);
      expect(File(done.filePath).existsSync(), isTrue);
    });

    test('a file deleted elsewhere (Music, Videos) leaves the list', () async {
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.completed);
      await s().forgetFile(t.filePath);
      expect(s().tasks, isEmpty);
    });
  });

  group('app restart', () {
    DownloadTask saved(String id, DownloadStatus status) => DownloadTask(
      id: id,
      title: id,
      kind: DownloadKind.video,
      extension: 'mp4',
      filePath: '${h.root}/Video/$id.mp4',
      createdAt: DateTime(2026),
      videoId: 'abcdefghijk',
      status: status,
      totalBytes: 10000,
    );

    test('downloads cut off by an app kill come back paused, with the bytes they have on disk', () async {
      final running = saved('running', DownloadStatus.running);
      final queued = saved('queued', DownloadStatus.queued);
      final done = saved('done', DownloadStatus.completed);
      final work = Directory('${h.ytdlp.workRoot}/running')..createSync(recursive: true);
      File('${work.path}/running.f137.mp4.part').writeAsBytesSync(List.filled(4321, 1));
      await h.downloads.write(AppConstants.kDownloadTasks, [running.toJson(), queued.toJson(), done.toJson()]);

      final again = await h.start();
      expect(again.tasks.map((t) => t.status.value), [DownloadStatus.paused, DownloadStatus.paused, DownloadStatus.completed]);
      await DownloadHarness.until(() => again.tasks.first.receivedBytes.value == 4321, what: 'the size on disk');
      expect(h.ytdlp.calls, isEmpty, reason: 'nothing restarts by itself');
    });

    test('the list survives a restart: names, links and states', () async {
      final t = await s().enqueueDirect(url: origin.url.toString());
      await DownloadHarness.status(t, DownloadStatus.completed);
      final again = await h.start();
      expect(again.tasks.single.filePath, t.filePath);
      expect(again.tasks.single.url, t.url);
      expect(again.tasks.single.status.value, DownloadStatus.completed);
    });
  });

  group('clean temporary files', () {
    test('leftovers no download owns are deleted; a paused download keeps its partial data', () async {
      final paused = await slow(name: 'paused.mp4');
      await someBytes(paused);
      s().pause(paused);
      await DownloadHarness.status(paused, DownloadStatus.paused);
      final orphanPart = File('${h.root}/Video/old.mp4.part')..writeAsBytesSync(List.filled(500, 0));
      final orphanWork = Directory('${h.ytdlp.workRoot}/gone-task')..createSync(recursive: true);
      File('${orphanWork.path}/x.part').writeAsBytesSync(List.filled(700, 0));

      final freed = await s().cleanTemporaryFiles();
      expect(freed, 1200);
      expect(orphanPart.existsSync(), isFalse);
      expect(orphanWork.existsSync(), isFalse);
      expect(File(paused.partPath).existsSync(), isTrue);
    });
  });

  group('notification', () {
    Future<void> tapAction(String action) async {
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'toomu/download_notify',
        codec.encodeMethodCall(MethodCall('action', action)),
        (_) {},
      );
    }

    test('shows running downloads with their progress, and goes away when none run', () async {
      final t = await slow();
      await someBytes(t);
      await DownloadHarness.until(
        () => h.notifications.any((c) => c.method == 'update' && '${c.arguments}'.contains(t.id)),
        what: 'a progress notification',
      );
      final update = h.notifications.lastWhere((c) => c.method == 'update').arguments as Map;
      expect(update['title'], 'Downloading 1 files');
      expect((update['items'] as List).single['id'], t.id);
      s().pause(t);
      await DownloadHarness.until(() => h.notifications.last.method == 'stop', what: 'the notification to stop');
    });

    test('its Pause and Cancel buttons pause or delete that download; Pause all pauses everything', () async {
      final a = await slow(name: 'a.mp4');
      final b = await slow(name: 'b.mp4');
      await tapAction('pause:${a.id}');
      await DownloadHarness.status(a, DownloadStatus.paused);
      await tapAction('cancel:${b.id}');
      await DownloadHarness.until(() => !s().tasks.contains(b), what: 'b to be deleted');

      s().resume(a);
      await DownloadHarness.status(a, DownloadStatus.running);
      await tapAction('pauseAll');
      await DownloadHarness.status(a, DownloadStatus.paused);
    });
  });
}

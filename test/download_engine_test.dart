import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/services/download_service.dart';

const _mb = 1024 * 1024;

int byteAt(int i) => (i * 131 + (i >> 13)) & 0xff;

class FileServer {
  FileServer(this.length);

  final int length;
  final Set<int> slowStarts = {};
  final List<int> starts = [];
  bool ignoresRanges = false;
  int served = 0;
  int _busy = 0;

  /// Most requests open at the same time.
  int maxBusy = 0;

  /// When set, bodies pause after their first bytes until this many requests
  /// are open at once, so "N connections" doesn't depend on timing: on a
  /// busy machine early pieces could otherwise finish before the last
  /// request is accepted. Released for everyone after [holdLimit] if
  /// never reached.
  int holdUntilOpen = 0;
  Duration holdLimit = const Duration(seconds: 5);
  final _allOpen = Completer<void>();

  /// When set, the server stops sending once it has served this many
  /// bytes, until [release]: a test that pauses mid-download then always
  /// catches it in the middle, however fast or slow the machine is.
  int? stallAfter;
  Completer<void> _released = Completer<void>();

  /// Sends again (and no longer stalls).
  void release() {
    stallAfter = null;
    if (!_released.isCompleted) _released.complete();
    _released = Completer<void>();
  }

  late HttpServer server;

  Future<void> idle() async {
    while (_busy > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers.value('range') ?? '');
      final ranged = m != null && !ignoresRanges;
      final from = ranged ? int.parse(m[1]!) : 0;
      final to = ranged ? (int.parse(m[2]!) < length ? int.parse(m[2]!) : length - 1) : length - 1;
      starts.add(from);
      _busy++;
      if (_busy > maxBusy) maxBusy = _busy;
      if (holdUntilOpen > 0 && _busy >= holdUntilOpen && !_allOpen.isCompleted) _allOpen.complete();
      final res = req.response..contentLength = to - from + 1;
      if (ranged) {
        res
          ..statusCode = 206
          ..headers.set('content-range', 'bytes $from-$to/$length');
      }
      try {
        for (var pos = from; pos <= to; pos += 64 << 10) {
          final stall = stallAfter;
          if (stall != null && served >= stall) await _released.future;
          final end = pos + (64 << 10) - 1 < to ? pos + (64 << 10) - 1 : to;
          res.add(Uint8List.fromList([for (var i = pos; i <= end; i++) byteAt(i)]));
          await res.flush();
          served += end - pos + 1;
          // After the first bytes (headers only don't go out): the opening
          // request must arrive so the client starts the others.
          if (holdUntilOpen > 0 && pos == from) {
            await _allOpen.future.timeout(
              holdLimit,
              onTimeout: () {
                if (!_allOpen.isCompleted) _allOpen.complete(); // never reached: stop holding anyone
              },
            );
          }
          if (slowStarts.contains(from)) await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await res.close();
      } catch (_) {
        // The client hung up (pause).
      } finally {
        _busy--;
      }
    });
  }

  RangeRequest get request =>
      (from, to) => (url: Uri.parse('http://127.0.0.1:${server.port}/file.mp4'), headers: {'Range': 'bytes=$from-$to'});
}

void main() {
  group('yt-dlp work folder', () {
    late Directory tmp;
    late String root, legacy;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('work');
      root = '${tmp.path.replaceAll(r'\', '/')}/Toomu/.work';
      legacy = '${tmp.path.replaceAll(r'\', '/')}/cache/ytdlp-work';
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('new downloads work next to the finished files', () {
      expect(DownloadService.workDirFor('42', root: root, legacyRoot: legacy), '$root/42');
    });

    test('a paused download from before the move resumes in its old folder', () {
      Directory('$legacy/42').createSync(recursive: true);
      expect(DownloadService.workDirFor('42', root: root, legacyRoot: legacy), '$legacy/42');
    });

    test('once a task has a folder next to the files, that one is used', () {
      Directory('$legacy/42').createSync(recursive: true);
      Directory('$root/42').createSync(recursive: true);
      expect(DownloadService.workDirFor('42', root: root, legacyRoot: legacy), '$root/42');
    });

    test('without a folder next to the files (it could not be made) the app cache is used', () {
      expect(DownloadService.workDirFor('42', root: '', legacyRoot: legacy), '$legacy/42');
      expect(DownloadService.workDirFor('42', root: '', legacyRoot: ''), '');
    });
  });

  group('direct downloads over several connections', () {
    const total = 35 * _mb + 77;
    late Directory tmp;
    late String part;
    late FileServer origin;
    final service = DownloadService();

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('fetch');
      part = '${tmp.path.replaceAll(r'\', '/')}/movie.mp4.part';
      origin = FileServer(total);
      await origin.start();
    });
    tearDown(() async {
      await origin.server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    Future<void> fetch({CancelToken? token, void Function(int)? onBytes}) => service.fetchParallel(
      total,
      part,
      Directory(DownloadTask.chunksDirOf(part)),
      4,
      origin.request,
      token ?? CancelToken(),
      onBytes ?? (_) {},
    );

    void expectWholeFile() {
      final bytes = File(part).readAsBytesSync();
      expect(bytes.length, total);
      for (var i = 0; i < total; i++) {
        if (bytes[i] != byteAt(i)) fail('wrong byte at $i');
      }
      expect(Directory(DownloadTask.chunksDirOf(part)).existsSync(), isFalse, reason: 'temp pieces are gone');
    }

    test('a whole download is byte-exact', () async {
      var last = 0;
      await fetch(onBytes: (b) => last = b);
      expectWholeFile();
      expect(last, total);
    });

    test('a paused download resumes without fetching its saved bytes again', () async {
      origin.stallAfter = 16 * _mb;
      final token = CancelToken();
      await expectLater(
        fetch(
          token: token,
          onBytes: (b) {
            if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
          },
        ),
        throwsA(anything),
      );
      origin.release();
      await origin.idle();
      // What the first run saved, per piece, from its progress record.
      final journal = jsonDecode(File('${DownloadTask.chunksDirOf(part)}/written.json').readAsStringSync()) as Map;
      final chunk = journal['chunk'] as int;
      final written = (journal['written'] as List).cast<int>();
      final saved = [
        for (var i = 0; i < written.length; i++)
          if (written[i] > 0) (from: i * chunk, to: i * chunk + written[i]),
      ];
      expect(written.fold(0, (a, b) => a + b), greaterThan(8 * _mb), reason: 'the pause came mid-download');
      origin.starts.clear();
      await fetch();
      expectWholeFile();
      // Counting bytes served would also count what a connection still
      // pushes after the client dropped it (a busy machine is slow to
      // hang up); where the requests start is exact.
      for (final start in origin.starts) {
        expect(
          saved.any((r) => start >= r.from && start < r.to),
          isFalse,
          reason: 'the second run asked again for saved bytes at $start',
        );
      }
    });

    test('pieces go straight into the file: no second copy of the data at the end', () async {
      origin.stallAfter = 16 * _mb;
      final token = CancelToken();
      await expectLater(
        fetch(
          token: token,
          onBytes: (b) {
            if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
          },
        ),
        throwsA(anything),
      );
      origin.release();
      final temp = Directory(DownloadTask.chunksDirOf(part)).listSync().map((e) => e.uri.pathSegments.last);
      expect(temp, ['written.json'], reason: 'only the progress record, no per-piece copies');
    });

    test('a paused download shows the bytes it saved, not the length of its gappy file', () async {
      origin.stallAfter = 16 * _mb;
      final token = CancelToken();
      await expectLater(
        fetch(
          token: token,
          onBytes: (b) {
            if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
          },
        ),
        throwsA(anything),
      );
      origin.release();
      await origin.idle();
      final shown = DownloadService.partBytesOnDisk(part);
      expect(shown, greaterThan(8 * _mb));
      expect(shown, lessThan(File(part).lengthSync()), reason: 'later pieces were started, earlier ones not finished');
      int? resumedAt;
      await fetch(onBytes: (b) => resumedAt ??= b);
      expect(resumedAt, shown);
      expectWholeFile();
    });

    test('a part file that has its full length but still has gaps is not taken as finished', () async {
      File(part).writeAsBytesSync(List.filled(100, 0));
      expect(DownloadService.partComplete(part, 100), isTrue);
      Directory(DownloadTask.chunksDirOf(part)).createSync();
      expect(DownloadService.partComplete(part, 100), isFalse);
    });

    test('a slow connection hands half its piece to an idle one at the end', () async {
      origin.slowStarts.add(0);
      await fetch();
      expectWholeFile();
      expect(origin.starts.any((s) => s > 0 && s < 10 * _mb), isTrue, reason: 'piece 0 was split');
    });

    test('pieces saved by the previous version of the app are kept on resume', () async {
      final chunks = Directory(DownloadTask.chunksDirOf(part))..createSync(recursive: true);
      File('${chunks.path}/0').writeAsBytesSync([for (var i = 0; i < 10 * _mb; i++) byteAt(i)]);
      File('${chunks.path}/1').writeAsBytesSync([for (var i = 10 * _mb; i < 13 * _mb; i++) byteAt(i)]);
      File('${chunks.path}/0.1').writeAsBytesSync([1, 2, 3]);
      await fetch();
      expectWholeFile();
      expect(origin.served, greaterThanOrEqualTo(total - 13 * _mb));
      // Where requests start, not bytes served: a busy machine is slow to
      // hang up, and the server counts what it pushed meanwhile.
      for (final start in origin.starts) {
        expect(start >= 0 && start < 13 * _mb, isFalse, reason: 'saved bytes asked for again at $start');
      }
    });
  });

  group('starting a download', () {
    late Directory tmp;
    late String part;
    late FileServer origin;
    final service = DownloadService();

    setUp(() => tmp = Directory.systemTemp.createTempSync('start'));
    tearDown(() async {
      await origin.server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    Future<void> download(int total, {int connections = 8, int holdUntilOpen = 0}) async {
      origin = FileServer(total)..holdUntilOpen = holdUntilOpen;
      await origin.start();
      part = '${tmp.path.replaceAll(r'\', '/')}/file.zip.part';
      await service.downloadUrl(
        Uri.parse('http://127.0.0.1:${origin.server.port}/file.zip'),
        const {},
        part,
        connections: connections,
        token: CancelToken(),
        onBytes: (_) {},
      );
      final bytes = File(part).readAsBytesSync();
      expect(bytes.length, total);
      for (var i = 0; i < total; i++) {
        if (bytes[i] != byteAt(i)) fail('wrong byte at $i');
      }
    }

    test('a 5 MB file uses several connections, not one like a browser', () async {
      await download(5 * _mb, holdUntilOpen: 4);
      expect(origin.maxBusy, greaterThanOrEqualTo(4), reason: '4 requests open at the same time');
    });

    test('no separate size check: the first request already brings the start of the file', () async {
      await download(30 * _mb + 5);
      expect(origin.starts.where((s) => s == 0), hasLength(1), reason: 'byte 0 asked for once');
      // The first answer brings bytes 0 to 1 MB; none of them is asked for again.
      expect(
        origin.starts.where((s) => s > 0 && s < _mb),
        isEmpty,
        reason: 'the first answer was used, not thrown away',
      );
    });

    test('a file smaller than the first request comes in that one request', () async {
      await download(300 * 1024);
      expect(origin.starts, [0]);
    });

    test('a server that ignores ranges sends the whole file in the first answer', () async {
      final total = 3 * _mb + 11;
      origin = FileServer(total)..ignoresRanges = true;
      await origin.start();
      part = '${tmp.path.replaceAll(r'\', '/')}/file.zip.part';
      await service.downloadUrl(
        Uri.parse('http://127.0.0.1:${origin.server.port}/file.zip'),
        const {},
        part,
        connections: 8,
        token: CancelToken(),
        onBytes: (_) {},
      );
      expect(File(part).lengthSync(), total);
      expect(origin.starts, [0], reason: 'one request in all');
    });

    test('16 connections are used when chosen', () async {
      await download(160 * _mb, connections: 16, holdUntilOpen: 16);
      expect(origin.maxBusy, greaterThanOrEqualTo(16), reason: '16 requests open at the same time');
    });
  });

  group('piece size', () {
    test('pieces are sized so every connection gets work, 1 to 10 MB each', () {
      expect(DownloadService.pieceSizeFor(5 * _mb, 8), _mb);
      expect(DownloadService.pieceSizeFor(16 * _mb, 8), 2 * _mb);
      expect(DownloadService.pieceSizeFor(15 * _mb, 8), 15 * _mb ~/ 8);
      expect(DownloadService.pieceSizeFor(500 * _mb, 8), 10 * _mb);
      expect(DownloadService.pieceSizeFor(300 * 1024, 8), _mb);
    });
  });

  group('streams from other sites on Android', () {
    test('segments are fetched in parallel with the chosen number of connections', () {
      expect(DownloadService.fragmentArgs(DownloadSource.stream, 8), ['--concurrent-fragments', '8']);
      expect(DownloadService.fragmentArgs(DownloadSource.stream, 16), ['--concurrent-fragments', '16']);
    });

    test('one connection, or a source that is one file, gets no extra arguments', () {
      expect(DownloadService.fragmentArgs(DownloadSource.stream, 1), isEmpty);
      expect(DownloadService.fragmentArgs(DownloadSource.tiktok, 8), isEmpty);
    });
  });
}

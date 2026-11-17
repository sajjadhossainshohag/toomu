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
  int served = 0;
  int _busy = 0;
  late HttpServer server;

  Future<void> idle() async {
    while (_busy > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers.value('range') ?? '')!;
      final from = int.parse(m[1]!), to = int.parse(m[2]!);
      starts.add(from);
      _busy++;
      final res = req.response
        ..statusCode = 206
        ..contentLength = to - from + 1
        ..headers.set('content-range', 'bytes $from-$to/$length');
      try {
        for (var pos = from; pos <= to; pos += 64 << 10) {
          final end = pos + (64 << 10) - 1 < to ? pos + (64 << 10) - 1 : to;
          res.add(Uint8List.fromList([for (var i = pos; i <= end; i++) byteAt(i)]));
          await res.flush();
          served += end - pos + 1;
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

  RangeRequest get request => (from, to) => (
        url: Uri.parse('http://127.0.0.1:${server.port}/file.mp4'),
        headers: {'Range': 'bytes=$from-$to'},
      );
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

    test('without a folder next to the files (iOS, or it could not be made) the app cache is used', () {
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
      final token = CancelToken();
      await expectLater(fetch(token: token, onBytes: (b) {
        if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
      }), throwsA(anything));
      await origin.idle();
      final saved = File(part).existsSync() || Directory(DownloadTask.chunksDirOf(part)).existsSync();
      expect(saved, isTrue);
      origin.served = 0;
      await fetch();
      expectWholeFile();
      expect(origin.served, lessThan(total - 8 * _mb), reason: 'the second run skipped what the first saved');
    });

    test('pieces go straight into the file: no second copy of the data at the end', () async {
      final token = CancelToken();
      await expectLater(fetch(token: token, onBytes: (b) {
        if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
      }), throwsA(anything));
      final temp = Directory(DownloadTask.chunksDirOf(part)).listSync().map((e) => e.uri.pathSegments.last);
      expect(temp, ['written.json'], reason: 'only the progress record, no per-piece copies');
    });

    test('a paused download shows the bytes it saved, not the length of its gappy file', () async {
      final token = CancelToken();
      await expectLater(fetch(token: token, onBytes: (b) {
        if (b > 12 * _mb && !token.isCancelled) token.cancel('pause');
      }), throwsA(anything));
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
      expect(origin.served, lessThan(total - 10 * _mb), reason: 'the saved 10 MB piece was not fetched again');
    });
  });
}

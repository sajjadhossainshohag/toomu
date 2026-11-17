import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/services/download_service.dart';

const _mb = 1024 * 1024;

// Sends part of each answer, then nothing, with the connection left open:
// what a phone sees when Wi-Fi or mobile data drops mid-download.
class SilentServer {
  SilentServer(this.length, {this.sendBeforeSilence = 256 * 1024});

  final int length;
  final int sendBeforeSilence;
  final _silence = Completer<void>();
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers.value('range') ?? '')!;
      final from = int.parse(m[1]!), to = int.parse(m[2]!) < length ? int.parse(m[2]!) : length - 1;
      final res = req.response
        ..statusCode = 206
        ..contentLength = to - from + 1
        ..headers.set('content-range', 'bytes $from-$to/$length');
      final n = (to - from + 1) < sendBeforeSilence ? to - from + 1 : sendBeforeSilence;
      res.add(Uint8List(n));
      await res.flush();
      await _silence.future;
      try {
        await res.close();
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    if (!_silence.isCompleted) _silence.complete();
    await server.close(force: true);
  }
}

void main() {
  group('the connection goes silent mid-download', () {
    late SilentServer origin;
    late Directory tmp;

    setUp(() async {
      DownloadService.stallLimit = const Duration(seconds: 2);
      origin = SilentServer(20 * _mb);
      await origin.start();
      tmp = Directory.systemTemp.createTempSync('silent');
    });
    tearDown(() async {
      await origin.stop();
      tmp.deleteSync(recursive: true);
    });

    Future<Object?> download(int connections) async {
      try {
        await DownloadService().downloadUrl(
          Uri.parse('http://127.0.0.1:${origin.server.port}/f.mp4'),
          const {},
          '${tmp.path.replaceAll(r'\', '/')}/f.mp4.part',
          connections: connections,
          token: CancelToken(),
          onBytes: (_) {},
        );
        return null;
      } catch (e) {
        return e;
      }
    }

    for (final connections in [1, 8]) {
      test('a download that stops receiving data ends as "connection lost", not stuck forever ($connections connections)', () async {
        final error = await download(connections).timeout(const Duration(seconds: 40), onTimeout: () => 'still waiting');
        expect(error, isNot('still waiting'), reason: 'the download hung instead of failing');
        expect(error, isNotNull);
        expect(DownloadService.isNetworkError(error!), isTrue, reason: '$error');
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  });

  group('offline', () {
    test('when the server cannot be reached at all, the download hands over to "connection lost" at once', () async {
      DownloadService.stallLimit = const Duration(seconds: 2);
      final origin = SilentServer(20 * _mb);
      await origin.start();
      final tmp = Directory.systemTemp.createTempSync('offline');
      addTearDown(() async {
        await origin.stop();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final port = origin.server.port;
      final sw = Stopwatch()..start();
      // Stop taking new connections; the open one stays silent, like a dropped network.
      Timer(const Duration(milliseconds: 500), () => origin.server.close());
      Object? error;
      try {
        await DownloadService().downloadUrl(
          Uri.parse('http://127.0.0.1:$port/f.mp4'),
          const {},
          '${tmp.path.replaceAll(r'\', '/')}/f.mp4.part',
          connections: 1,
          token: CancelToken(),
          onBytes: (_) {},
        );
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(DownloadService.isNetworkError(error!), isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 8)), reason: 'no slow retries while offline');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('which failures wait for the network', () {
    test('errors Android shows when Wi-Fi or mobile data drops', () {
      for (final message in [
        'ERROR: [download] Got error: [Errno 103] Software caused connection abort',
        'ERROR: <urlopen error [Errno 113] No route to host>',
        "ERROR: [download] Got error: ('Connection broken: IncompleteRead(1048576 bytes read, 9437184 more expected)', IncompleteRead(1048576 bytes read))",
        'ERROR: [download] Got error: EOF occurred in violation of protocol (_ssl.c:2427)',
        'errorCode=6 Network problem has occurred. cause:Failed to establish connection',
        'ERROR: aria2c exited with code 6',
        'ERROR: aria2c exited with code 19',
        'ERROR: [download] Got error: [Errno 101] Network is unreachable',
        'ERROR: Unable to download webpage: <urlopen error [Errno 7] No address associated with hostname>',
      ]) {
        expect(DownloadService.isNetworkError(YtDlpException(message)), isTrue, reason: message);
      }
      expect(DownloadService.isNetworkError(TimeoutException('no data for 30 s')), isTrue);
      expect(DownloadService.isNetworkError(StateError('Piece at 0 ended early.')), isTrue);
    });

    test('real failures are not mistaken for a lost connection', () {
      for (final message in [
        'ERROR: unable to download video data: HTTP Error 403: Forbidden',
        'ERROR: [youtube] abc: Video unavailable',
        'ERROR: unable to write data: [Errno 28] No space left on device',
        'ERROR: aria2c exited with code 22',
      ]) {
        expect(DownloadService.isNetworkError(YtDlpException(message)), isFalse, reason: message);
      }
      expect(DownloadService.isNetworkError(const FileSystemException('No space left on device')), isFalse);
    });
  });

  group('waiting for the network', () {
    test('a server on its own port counts as back online', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final link = Uri.parse('http://127.0.0.1:${server.port}/file.zip');
      expect(await DownloadService.online(link), isTrue);
      await server.close(force: true);
      expect(await DownloadService.online(link), isFalse);
    });

    test('a download that made progress before losing the connection keeps retrying', () {
      expect(DownloadService.retriesAfterLoss(previous: 19, progressed: true), 1);
      expect(DownloadService.retriesAfterLoss(previous: 3, progressed: false), 4);
    });
  });
}

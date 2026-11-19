import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/parallel_download.dart';

/// Serves [data] with Range support; counts open connections at once.
class _Server {
  _Server(this.data);
  final Uint8List data;
  late HttpServer server;
  bool ignoresRanges = false;
  int failNext = 0;
  int open = 0;
  int maxOpen = 0;

  String get url => 'http://127.0.0.1:${server.port}/toomu.apk';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      open++;
      if (open > maxOpen) maxOpen = open;
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers.value('range') ?? '');
      final ranged = m != null && !ignoresRanges;
      final from = ranged ? int.parse(m[1]!) : 0;
      var to = ranged ? int.parse(m[2]!) : data.length - 1;
      if (to >= data.length) to = data.length - 1;
      final res = req.response;
      if (ranged && failNext > 0 && from > 0) {
        failNext--;
        res.statusCode = 500;
      } else {
        res.statusCode = ranged ? 206 : 200;
        if (ranged) res.headers.set('content-range', 'bytes $from-$to/${data.length}');
        res.contentLength = to - from + 1;
        await Future<void>.delayed(const Duration(milliseconds: 20)); // overlap the workers
        res.add(data.sublist(from, to + 1));
      }
      await res.close();
      open--;
    });
  }
}

void main() {
  late Directory tmp;
  late _Server origin;
  final data = Uint8List.fromList(List.generate(1000003, (i) => (i * 31 + 7) & 0xff));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('toomu_update_');
    origin = _Server(data);
    await origin.start();
  });
  tearDown(() async {
    await origin.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('the app update downloads over several connections at once', () async {
    final path = '${tmp.path}/u.apk';
    var last = (0, 0);
    await parallelDownload(Dio(), origin.url, path, connections: 8, piece: 64 << 10, onProgress: (r, t) => last = (r, t));
    expect(File(path).readAsBytesSync(), data);
    expect(origin.maxOpen, greaterThan(1));
    expect(last, (data.length, data.length));
  });

  test('a server that ignores ranges still gives the whole update', () async {
    origin.ignoresRanges = true;
    final path = '${tmp.path}/u.apk';
    await parallelDownload(Dio(), origin.url, path, piece: 64 << 10);
    expect(File(path).readAsBytesSync(), data);
  });

  test('a piece that fails once is fetched again, and progress is not counted twice', () async {
    origin.failNext = 2;
    final path = '${tmp.path}/u.apk';
    var last = 0;
    await parallelDownload(Dio(), origin.url, path, piece: 64 << 10, retryDelay: Duration.zero, onProgress: (r, _) => last = r);
    expect(File(path).readAsBytesSync(), data);
    expect(last, data.length);
  });

  test('a piece that keeps failing fails the update and leaves no file', () async {
    origin.failNext = 1000;
    final path = '${tmp.path}/u.apk';
    await expectLater(
      parallelDownload(Dio(), origin.url, path, piece: 64 << 10, retryDelay: Duration.zero),
      throwsA(anything),
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('a connection that drops for a while (screen off) is waited out, not failed', () async {
    origin.failNext = 4; // more failures than the old 3 tries
    final path = '${tmp.path}/u.apk';
    await parallelDownload(Dio(), origin.url, path, connections: 1, piece: 64 << 10, retryDelay: const Duration(milliseconds: 5));
    expect(File(path).readAsBytesSync(), data);
  });
}

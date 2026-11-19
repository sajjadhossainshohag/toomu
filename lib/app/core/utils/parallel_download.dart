import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Downloads [url] to [path] over [connections] connections: workers take
/// [piece]-sized ranges in turn, so one slow connection holds back only its
/// own piece. A server that ignores ranges (200 instead of 206) is read in
/// one go. A failed piece is tried [retries] times, waiting longer each
/// time. [onProgress] gets (received, total); total is 0 while unknown.
///
/// Used for the app update (GitHub release assets): one connection is held
/// to ~1.5 MB/s there, 8 got ~2.3 MB/s on the same line; it uses 12.
Future<void> parallelDownload(
  Dio dio,
  String url,
  String path, {
  int connections = 12,
  int piece = 4 << 20,
  int retries = 6,
  Duration retryDelay = const Duration(seconds: 2),
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final raf = file.openSync(mode: FileMode.write);
  var received = 0;
  var total = 0;
  void got(int n) {
    received += n;
    onProgress?.call(received, total);
  }

  try {
    // The first piece also tells whether ranges work and how big the file is.
    final first = await _get(dio, url, 0, piece - 1, cancelToken);
    final ranged = first.statusCode == 206;
    total = ranged
        ? _totalFromContentRange(first.headers.value('content-range')) ?? 0
        : int.tryParse(first.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    if (!ranged || total <= piece) {
      await _readInto(raf, 0, first.data!.stream, got);
      return;
    }

    var next = 1; // piece 0 is the first answer
    final count = (total + piece - 1) ~/ piece;
    final failures = <Object>[];

    Future<void> runPiece(int i, Response<ResponseBody>? already) async {
      final start = i * piece;
      final end = (start + piece < total ? start + piece : total) - 1;
      for (var attempt = 0;; attempt++) {
        var done = 0;
        try {
          final r = already ?? await _get(dio, url, start, end, cancelToken);
          already = null;
          if (r.statusCode != 206) throw HttpException('Range not honored (${r.statusCode})', uri: Uri.parse(url));
          await _readInto(raf, start, r.data!.stream, (n) {
            done += n;
            got(n);
          });
          if (done != end - start + 1) throw HttpException('Short piece', uri: Uri.parse(url));
          return;
        } catch (e) {
          received -= done; // that piece starts over
          if (cancelToken?.isCancelled ?? false) rethrow;
          if (attempt + 1 >= retries || failures.isNotEmpty) rethrow;
          // Waits out a dropped connection (screen off, Wi-Fi to mobile data):
          // 2, 4, 6… s, about a minute in all by default.
          await Future<void>.delayed(retryDelay * (attempt + 1));
          if (cancelToken?.isCancelled ?? false) throw DioException.requestCancelled(requestOptions: RequestOptions(path: url), reason: 'canceled');
        }
      }
    }

    Future<void> worker(Response<ResponseBody>? firstAnswer) async {
      if (firstAnswer != null) await runPiece(0, firstAnswer);
      while (failures.isEmpty && next < count) {
        await runPiece(next++, null);
      }
    }

    final n = connections < 1 ? 1 : connections;
    await Future.wait([
      for (var w = 0; w < n; w++)
        worker(w == 0 ? first : null).catchError((Object e) {
          failures.add(e);
        }),
    ]);
    if (failures.isNotEmpty) throw failures.first;
  } catch (_) {
    raf.closeSync();
    if (file.existsSync()) file.deleteSync();
    rethrow;
  }
  raf.closeSync();
}

Future<Response<ResponseBody>> _get(Dio dio, String url, int from, int to, CancelToken? cancel) =>
    dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=$from-$to'},
        validateStatus: (s) => s == 200 || s == 206,
      ),
    );

/// Buffers the body and writes it at [offset]. Sync writes: Dart allows only
/// one async operation at a time on a RandomAccessFile.
Future<void> _readInto(RandomAccessFile raf, int offset, Stream<Uint8List> body, void Function(int) got) async {
  final buf = BytesBuilder(copy: false);
  await for (final chunk in body) {
    buf.add(chunk);
    got(chunk.length);
    // Big bodies (a server without ranges) are written as they come.
    if (buf.length >= 4 << 20) {
      raf.setPositionSync(offset);
      final bytes = buf.takeBytes();
      raf.writeFromSync(bytes);
      offset += bytes.length;
    }
  }
  if (buf.isNotEmpty) {
    raf.setPositionSync(offset);
    raf.writeFromSync(buf.takeBytes());
  }
}

int? _totalFromContentRange(String? v) => int.tryParse(v?.split('/').last ?? '');

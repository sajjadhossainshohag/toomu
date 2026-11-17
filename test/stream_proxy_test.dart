import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/yt_info.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/services/stream_proxy.dart';

/// A stand-in for YouTube's media servers with their measured rules: only
/// `range=` pieces up to 10 MB are served; the fast-lookup ("partial") link
/// refuses anything past its free minute; one connection drops mid-piece.
class FakeYoutube {
  FakeYoutube(this.length, {required this.freeBytes});

  final int length;
  final int freeBytes;
  late HttpServer server;
  int requests = 0;
  bool dropped = false;
  Socket? held;
  final connections = <int>{};

  static int byteAt(int i) => (i * 31 + 7) & 0xff;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests++;
      connections.add(req.connectionInfo!.remotePort);
      final q = req.uri.queryParameters;
      final res = req.response;
      final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(q['range'] ?? '');
      final from = m == null ? -1 : int.parse(m[1]!);
      final to = m == null ? -1 : int.parse(m[2]!);
      if (q['kind'] == 'liar') {
        // Ignores the range and sends the file from the start.
        res.contentLength = length;
        res.add([for (var i = 0; i < length; i++) byteAt(i)]);
        await res.close();
        return;
      }
      final refused = m == null ||
          q['kind'] == 'expired' ||
          req.headers.value('range') != null ||
          to - from + 1 > 10 << 20 ||
          to >= length ||
          (q['kind'] == 'partial' && to >= freeBytes);
      if (refused) {
        res.statusCode = 403;
        await res.close();
        return;
      }
      res.contentLength = to - from + 1;
      final bytes = [for (var i = from; i <= to; i++) byteAt(i)];
      if (held == null && q['kind'] == 'hang' && bytes.length > 4096) {
        // Half the piece, then the connection stays open with nothing more.
        final socket = held = await res.detachSocket();
        socket.add(bytes.sublist(0, bytes.length ~/ 2));
        await socket.flush();
        return;
      }
      if (!dropped && q['kind'] == 'full' && bytes.length > 4096) {
        // Half the piece, then the connection breaks.
        dropped = true;
        final socket = await res.detachSocket(); // headers (full length) sent
        socket.add(bytes.sublist(0, bytes.length ~/ 2));
        await socket.flush();
        socket.destroy();
        return;
      }
      res.add(bytes);
      await res.close();
    });
  }

  String url(String kind) => 'http://127.0.0.1:${server.port}/videoplayback?itag=137&clen=$length&kind=$kind';
}

Future<(int status, List<int> body, String? contentRange)> fetch(String url, {String? range}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    if (range != null) req.headers.set('range', range);
    final res = await req.close();
    final body = <int>[];
    try {
      await for (final d in res) {
        body.addAll(d);
      }
    } catch (_) {
      // Connection dropped: return what arrived.
    }
    return (res.statusCode, body, res.headers.value('content-range'));
  } finally {
    client.close(force: true);
  }
}

void main() {
  const length = 6 * 1024 * 1024 + 123;
  const free = 2500000;
  late FakeYoutube yt;
  late Completer<void> lookupDone;
  late StreamProxy proxy;
  var lookupFails = false;

  setUp(() async {
    // A short stall limit: the same stalls, found in a second, not 12 s.
    StreamProxy.stallLimit = const Duration(seconds: 1);
    StreamProxy.retryStep = const Duration(milliseconds: 20);
    yt = FakeYoutube(length, freeBytes: free);
    await yt.start();
    lookupDone = Completer<void>();
    lookupFails = false;
    proxy = StreamProxy(
      isMediaFile: (u) => u.path == '/videoplayback',
      fullLookup: (id) async {
        await lookupDone.future;
        if (lookupFails) throw StateError('lookup failed');
        return YtInfo(id: id, title: '', uploader: '', formats: [
          YtFormat(formatId: '136', ext: 'mp4', url: '${yt.url('full')}x'.replaceFirst('itag=137', 'itag=136')),
          YtFormat(formatId: '137', ext: 'mp4', url: yt.url('full')),
        ]);
      },
    );
    await proxy.init();
  });

  tearDown(() async {
    proxy.onClose();
    yt.held?.destroy();
    await yt.server.close(force: true);
  });

  bool matches(List<int> body, int from) {
    for (var i = 0; i < body.length; i++) {
      if (body[i] != FakeYoutube.byteAt(from + i)) return false;
    }
    return true;
  }

  test('plays a fast link past its free minute once full links arrive', () async {
    final local = proxy.wrap(yt.url('partial'), videoId: 'abc', partial: true);
    expect(local, startsWith('http://127.0.0.1:'));
    // Full links arrive while the player is already waiting at the limit.
    Timer(const Duration(milliseconds: 600), lookupDone.complete);
    final (status, body, contentRange) = await fetch(local, range: 'bytes=0-');
    expect(status, 206);
    expect(contentRange, 'bytes 0-${length - 1}/$length');
    expect(body.length, length);
    expect(matches(body, 0), isTrue);
    expect(yt.dropped, isTrue, reason: 'the dropped piece was asked for again');
  });

  test('a connection that goes silent mid-piece is asked again and the bytes stay exact', () async {
    lookupDone.complete();
    final local = proxy.wrap(yt.url('hang'), videoId: 'abc');
    final (status, body, _) = await fetch(local, range: 'bytes=0-');
    expect(status, 206);
    expect(body.length, length);
    expect(matches(body, 0), isTrue);
    expect(yt.held, isNotNull, reason: 'the silent connection happened');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a player that stops reading for longer than the stall limit is not a stall', () async {
    final big = FakeYoutube(40 << 20, freeBytes: 0);
    await big.start();
    addTearDown(() => big.server.close(force: true));
    final local = proxy.wrap(big.url('ok'), videoId: 'big');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final res = await (await client.getUrl(Uri.parse(local))).close();
    final body = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> sub;
    final done = Completer<void>();
    var paused = false;
    sub = res.listen((d) {
      body.add(d);
      if (!paused && body.length > 1 << 20) {
        paused = true;
        sub.pause();
        // Longer than the stall limit.
        Timer(StreamProxy.stallLimit * 3, sub.resume);
      }
    }, onDone: done.complete, onError: done.completeError);
    await done.future;
    final bytes = body.takeBytes();
    expect(bytes.length, 40 << 20);
    expect(matches(bytes, 0), isTrue);
    // 1 + 2 + 4 + 8 + 8 + 8 + 8 + 1 MB: a stall would have asked again.
    expect(big.requests, 8);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('playback reuses the connection of the link check before it', () async {
    lookupDone.complete();
    final link = yt.url('ok');
    expect(await YoutubeProvider.serves(link, const {}), isTrue);
    final (status, body, _) = await fetch(proxy.wrap(link, videoId: 'abc'), range: 'bytes=0-99');
    expect(status, 206);
    expect(matches(body, 0), isTrue);
    expect(yt.connections, hasLength(1));
  });

  test('serves exact ranges, suffix ranges and refuses ranges past the end', () async {
    lookupDone.complete();
    final local = proxy.wrap(yt.url('full'), videoId: 'abc');
    final mid = await fetch(local, range: 'bytes=100-199');
    expect(mid.$1, 206);
    expect(mid.$2.length, 100);
    expect(matches(mid.$2, 100), isTrue);
    expect(mid.$3, 'bytes 100-199/$length');

    final tail = await fetch(local, range: 'bytes=-500');
    expect(tail.$2.length, 500);
    expect(matches(tail.$2, length - 500), isTrue);

    final whole = await fetch(local);
    expect(whole.$1, 200);
    expect(whole.$2.length, length);

    final past = await fetch(local, range: 'bytes=$length-');
    expect(past.$1, 416);
  });

  test('a failed lookup ends the stream at the free minute instead of hanging', () async {
    lookupFails = true;
    final local = proxy.wrap(yt.url('partial'), videoId: 'abc', partial: true);
    Timer(const Duration(milliseconds: 300), lookupDone.complete);
    final (status, body, _) = await fetch(local, range: 'bytes=0-');
    expect(status, 206);
    expect(body.length, lessThan(length));
    expect(body.length, lessThanOrEqualTo(free));
    expect(matches(body, 0), isTrue);
  });

  test('a newer link for the same file replaces an expired one', () async {
    lookupDone.complete();
    final old = proxy.wrap(yt.url('expired'), videoId: 'abc');
    final local = proxy.wrap(yt.url('full'), videoId: 'abc');
    expect(local, old);
    final (status, body, _) = await fetch(local, range: 'bytes=0-99');
    expect(status, 206);
    expect(matches(body, 0), isTrue);
  });

  test('the same file keeps one address; other links pass through', () {
    lookupDone.complete();
    final a = proxy.wrap(yt.url('partial'), videoId: 'abc', partial: true);
    final b = proxy.wrap(yt.url('full'), videoId: 'abc');
    expect(a, b);
    expect(proxy.wrap('https://example.com/a.mp4'), 'https://example.com/a.mp4');
  });

  test("yt-dlp's download links are routed through the proxy, other entries left alone", () {
    lookupDone.complete();
    final media = yt.url('full');
    final json = jsonEncode({
      'id': 'abc',
      'formats': [
        {'format_id': '137', 'protocol': 'https', 'url': media, 'http_headers': {'User-Agent': 'x'}},
        {'format_id': 'sb0', 'protocol': 'mhtml', 'url': 'https://i.ytimg.com/sb/abc/storyboard.jpg'},
      ],
    });
    final routed = jsonDecode(proxy.routeInfoJson(json)) as Map<String, dynamic>;
    final formats = routed['formats'] as List;
    expect(formats[0]['url'], proxy.wrap(media, videoId: 'abc'));
    expect(formats[0]['url'], startsWith('http://127.0.0.1:'));
    expect(formats[1]['url'], 'https://i.ytimg.com/sb/abc/storyboard.jpg');
    expect(proxy.routeInfoJson('not json'), 'not json');
  });

  test('a server that ignores the range never gets wrong bytes into the output', () async {
    lookupDone.complete();
    final local = proxy.wrap(yt.url('liar'), videoId: 'abc');
    List<int> body;
    try {
      body = (await fetch(local, range: 'bytes=1000-1999')).$2;
    } on HttpException {
      body = const []; // closed before any byte: the player reports an error
    }
    expect(matches(body, 1000), isTrue, reason: 'whatever arrived is the right part');
    expect(body.length, lessThan(1000), reason: 'the stream is cut, not filled with other bytes');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('parseRange', () {
    expect(StreamProxy.parseRange(null, 1000), (0, 999, false));
    expect(StreamProxy.parseRange('bytes=0-', 1000), (0, 999, true));
    expect(StreamProxy.parseRange('bytes=10-20', 1000), (10, 20, true));
    expect(StreamProxy.parseRange('bytes=990-5000', 1000), (990, 999, true));
    expect(StreamProxy.parseRange('bytes=-100', 1000), (900, 999, true));
    expect(StreamProxy.parseRange('bytes=1000-', 1000), isNull);
  });
}

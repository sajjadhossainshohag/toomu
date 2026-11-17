import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/browser/image_menu.dart';
import 'package:toomu/app/services/download_service.dart';

/// 1×1 transparent PNG.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  const web = PageImage(
    src: 'https://img.example.com/posters/avatar-last-airbender.webp?w=300',
    alt: 'Poster of Avatar: The Last Airbender - Premiere',
    pageUrl: 'https://movies.example.com/avatar',
  );
  const inline = PageImage(src: 'data:image/png;base64,$_png');
  const blob = PageImage(src: 'blob:https://movies.example.com/1234-5678');

  group('what the menu offers (Chrome order)', () {
    test('a picture on the web gets every action', () {
      expect(imageActions(web, canCopyImage: true), [
        ImageAction.open,
        ImageAction.preview,
        ImageAction.copy,
        ImageAction.copyLink,
        ImageAction.download,
        ImageAction.lens,
        ImageAction.share,
      ]);
    });

    test('no "Copy image" where the clipboard takes no pictures', () {
      expect(imageActions(web, canCopyImage: false), isNot(contains(ImageAction.copy)));
    });

    test('inline and script-made pictures have no link to open, copy or search', () {
      for (final img in [inline, blob]) {
        expect(imageActions(img, canCopyImage: true), [
          ImageAction.preview,
          ImageAction.copy,
          ImageAction.download,
          ImageAction.share,
        ], reason: img.src);
      }
    });

    test('labels read like Chrome\'s', () {
      expect(ImageAction.lens.label, 'Search image with Google Lens');
      expect(ImageAction.download.label, 'Download image');
    });
  });

  group('menu title', () {
    test('the page\'s alt text, on one line', () {
      const img = PageImage(src: 'https://x.com/a.jpg', alt: '  Poster of\n  Avatar  ');
      expect(img.title, 'Poster of Avatar');
    });

    test('without alt text: the file\'s name from the link', () {
      expect(const PageImage(src: 'https://x.com/p/My%20Poster.jpg?x=1').title, 'My Poster.jpg');
      expect(const PageImage(src: 'https://x.com/').title, 'x.com');
    });

    test('inline pictures are just "Image"', () {
      expect(inline.title, 'Image');
      expect(blob.title, 'Image');
    });
  });

  test('Google Lens gets the picture\'s link, encoded', () {
    final u = lensUrl('https://img.example.com/a b.jpg?x=1&y=2');
    expect(u.host, 'lens.google.com');
    expect(u.path, '/uploadbyurl');
    expect(u.queryParameters['url'], 'https://img.example.com/a b.jpg?x=1&y=2');
  });

  group('saved file name', () {
    test('alt text + the type the server sent', () {
      expect(imageFileName(web, mimeType: 'image/jpeg'), 'Poster of Avatar The Last Airbender - Premiere.jpg');
    });

    test('the link\'s extension when the type is unknown', () {
      expect(imageFileName(web), 'Poster of Avatar The Last Airbender - Premiere.webp');
    });

    test('no alt text: the link\'s file name', () {
      expect(imageFileName(const PageImage(src: 'https://x.com/i/cat%20pic.JPEG')), 'cat pic.jpg');
      expect(imageFileName(const PageImage(src: 'https://x.com/thumb?id=9'), mimeType: 'image/png'), 'thumb.png');
    });

    test('nothing to go on: image.jpg', () {
      expect(imageFileName(blob), 'image.jpg');
      expect(imageFileName(inline, mimeType: 'image/svg+xml; charset=utf-8'), 'image.svg');
    });

    test('characters files can\'t have are dropped', () {
      expect(imageFileName(const PageImage(src: 'https://x.com/a.png', alt: 'a/b:c?*"<>|')), 'abc.png');
    });

    test('MIME type back from an extension (sharing, clipboard)', () {
      expect(imageMimeFor('jpg'), 'image/jpeg');
      expect(imageMimeFor('PNG'), 'image/png');
      expect(imageMimeFor('svg'), 'image/svg+xml');
    });
  });

  group('inline pictures', () {
    test('base64 data: links decode to their bytes and type', () {
      final d = decodeDataImage(inline.src)!;
      expect(d.mimeType, 'image/png');
      expect(d.bytes, base64Decode(_png));
    });

    test('percent-encoded SVG decodes too', () {
      final d = decodeDataImage('data:image/svg+xml,%3Csvg%2F%3E')!;
      expect(utf8.decode(d.bytes), '<svg/>');
    });

    test('not a data: link, or broken: nothing', () {
      expect(decodeDataImage('https://x.com/a.png'), isNull);
      expect(decodeDataImage('data:image/png;base64,%%%'), isNull);
    });
  });

  group('fetching the picture like the page did', () {
    late HttpServer server;
    final seen = <String, String?>{};
    var status = 200;

    setUp(() async {
      status = 200;
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        for (final h in ['referer', 'user-agent', 'cookie']) {
          seen[h] = req.headers.value(h);
        }
        req.response.statusCode = status;
        req.response.headers.set('content-type', 'image/png; charset=binary');
        req.response.add(base64Decode(_png));
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('web pictures are asked for with the page\'s Referer, User-Agent and cookies', () async {
      final img = PageImage(
        src: 'http://127.0.0.1:${server.port}/p.png',
        headers: const {'Referer': 'https://movies.example.com/avatar', 'User-Agent': 'UA-1', 'Cookie': 'sid=1'},
      );
      final got = await loadImageBytes(img, dio: Dio(), readBlob: (_) async => null);
      expect(got.bytes, base64Decode(_png));
      expect(got.mimeType, 'image/png');
      expect(seen, {'referer': 'https://movies.example.com/avatar', 'user-agent': 'UA-1', 'cookie': 'sid=1'});
    });

    test('a refused picture is an error, not an empty file', () async {
      status = 403;
      final img = PageImage(src: 'http://127.0.0.1:${server.port}/p.png');
      await expectLater(loadImageBytes(img, dio: Dio(), readBlob: (_) async => null), throwsA(isA<DioException>()));
    });

    test('inline pictures need no network', () async {
      final got = await loadImageBytes(inline, dio: Dio(), readBlob: (_) async => fail('no page needed'));
      expect(got.mimeType, 'image/png');
    });

    test('script-made (blob:) pictures are read inside the page', () async {
      String? asked;
      final got = await loadImageBytes(
        blob,
        dio: Dio(),
        readBlob: (src) async {
          asked = src;
          return 'data:image/png;base64,$_png';
        },
      );
      expect(asked, blob.src);
      expect(got.bytes, base64Decode(_png));
    });

    test('the page not handing over a blob picture is an error', () async {
      await expectLater(loadImageBytes(blob, dio: Dio(), readBlob: (_) async => null), throwsFormatException);
    });
  });

  group('saving an inline picture', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('imgsave'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory dirFor(DownloadKind k) => Directory('${tmp.path}/${k.name}')..createSync(recursive: true);

    test('becomes a finished download in Files, byte for byte', () async {
      final bytes = base64Decode(_png);
      final t = await DownloadService.writeFinished(
        bytes: bytes,
        fileName: 'Poster.png',
        mimeType: 'image/png',
        pageUrl: 'https://movies.example.com/avatar',
        dirFor: dirFor,
      );
      expect(t.status.value, DownloadStatus.completed);
      expect(t.kind, DownloadKind.file);
      expect(t.filePath, '${tmp.path}/file/Poster.png');
      expect(File(t.filePath).readAsBytesSync(), bytes);
      expect(t.totalBytes.value, bytes.length);
      expect(t.receivedBytes.value, bytes.length);
      expect(t.author, 'movies.example.com');
    });

    test('saving the same picture twice keeps both', () async {
      Future<DownloadTask> save() => DownloadService.writeFinished(bytes: [1, 2, 3], fileName: 'a.png', dirFor: dirFor);
      final first = await save();
      final second = await save();
      expect(first.filePath, endsWith('/a.png'));
      expect(second.filePath, endsWith('/a (1).png'));
    });

    test('a name an unfinished download will use is not taken', () async {
      final t = await DownloadService.writeFinished(
        bytes: [1],
        fileName: 'a.png',
        dirFor: dirFor,
        taken: (p) => p.endsWith('/a.png'),
      );
      expect(t.filePath, endsWith('/a (1).png'));
    });
  });
}

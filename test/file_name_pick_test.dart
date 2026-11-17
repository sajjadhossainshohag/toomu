import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/media_title.dart';

void main() {
  const page = 'https://files.example.com/f/abc';

  String pick({
    String? suggested,
    String url = 'https://cdn.example.net/d/a1b2c3d4e5f6a7b8c9d0',
    String pageTitle = '',
    String? disposition,
    List<String> hints = const [],
  }) =>
      downloadName(
        suggested: suggested,
        url: url,
        pageTitle: pageTitle,
        pageUrl: page,
        contentDisposition: disposition,
        pageHints: hints,
      );

  group("the server's own file name", () {
    test('a Bengali name sent the standard UTF-8 way is kept, not lost to "downloadfile.bin"', () {
      expect(
        pick(
          suggested: 'downloadfile.bin',
          disposition: "attachment; filename*=UTF-8''%E0%A6%86%E0%A6%AE%E0%A6%BE%E0%A6%B0%20%E0%A6%97%E0%A6%BE%E0%A6%A8.mp3",
        ),
        'আমার গান.mp3',
      );
    });

    test('the UTF-8 form wins over the plain fallback name', () {
      expect(pick(disposition: "attachment; filename=\"fallback.mp4\"; filename*=UTF-8''Caf%C3%A9%20Night.mp4"), 'Café Night.mp4');
    });

    test('quoted names may hold semicolons; unquoted ones spaces', () {
      expect(pick(disposition: 'attachment; filename="Movie; Part 1.mkv"'), 'Movie; Part 1.mkv');
      expect(pick(disposition: 'attachment; filename=Report 2024.pdf'), 'Report 2024.pdf');
    });

    test('UTF-8 bytes read as Latin-1 by the way are repaired', () {
      final garbled = latin1.decode(utf8.encode('আমার.mp3'));
      expect(pick(disposition: 'attachment; filename="$garbled"'), 'আমার.mp3');
    });

    test('a percent-encoded name and folder parts are cleaned up', () {
      expect(pick(disposition: 'attachment; filename="My%20Holiday.mp4"'), 'My Holiday.mp4');
      expect(pick(disposition: r'attachment; filename="C:\Users\me\clip.mp4"'), 'clip.mp4');
    });

    test('a coded name from the server still gives way to the page title', () {
      expect(
        pick(disposition: 'attachment; filename="7f3a9c2e1b8d4f60aa.mkv"', pageTitle: 'Dune Part Two (2024) | Example'),
        'Dune Part Two (2024).mkv',
      );
    });
  });

  group('a name inside the link', () {
    test('cloud storage links carry the name in response-content-disposition', () {
      expect(
        pick(
          suggested: 'abc123',
          url: 'https://bucket.s3.amazonaws.com/abc123?response-content-disposition=attachment%3B%20filename%3D%22Dune.Part.Two.2024.mkv%22&X-Amz-Signature=ff',
        ),
        'Dune.Part.Two.2024.mkv',
      );
    });

    test('a filename or file parameter is used', () {
      expect(pick(suggested: 'get.php', url: 'https://x.com/get.php?id=9&file=Inception.2010.1080p.mkv'), 'Inception.2010.1080p.mkv');
      expect(pick(suggested: 'dl', url: 'https://x.com/dl?filename=My+Song.mp3'), 'My Song.mp3');
    });

    test('an encoded file name in the path is decoded', () {
      expect(
        pick(suggested: 'My%20Holiday%20Video.mp4', url: 'https://x.com/v/My%20Holiday%20Video.mp4'),
        'My Holiday Video.mp4',
      );
    });
  });

  group('falling back to the page', () {
    test('Android\'s "downloadfile.bin" never makes a video a .bin file', () {
      expect(pick(suggested: 'downloadfile.bin', pageTitle: 'Inception (2010) | Example'), 'Inception (2010)');
    });

    test('a generic page title gives way to the page heading', () {
      expect(
        pick(
          suggested: 'a1b2c3d4e5f6a7b8c9.mkv',
          pageTitle: 'Download File',
          hints: ['', 'The.Odyssey.2026.1080p.mkv'],
        ),
        'The.Odyssey.2026.1080p.mkv',
      );
    });

    test('the share title is used when there is no heading', () {
      expect(
        pick(suggested: 'a1b2c3d4e5f6a7b8c9.mp4', pageTitle: 'Loading...', hints: ['Interstellar (2014)', '']),
        'Interstellar (2014).mp4',
      );
    });

    test('with nothing better, the server name is kept as it came', () {
      expect(pick(suggested: 'a1b2c3d4e5f6a7b8c9.mp4', pageTitle: 'Just a moment...'), 'a1b2c3d4e5f6a7b8c9.mp4');
      expect(pick(suggested: null, url: 'https://x.com/'), 'download');
    });
  });
}

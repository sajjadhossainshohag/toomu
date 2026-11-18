import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/formatters.dart';
import 'package:toomu/app/core/utils/link_parser.dart';

void main() {
  group('LinkParser', () {
    test('extracts id from watch, short and shared-text links', () {
      expect(LinkParser.youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(LinkParser.youtubeVideoId('https://youtu.be/dQw4w9WgXcQ?si=abc'), 'dQw4w9WgXcQ');
      expect(LinkParser.youtubeVideoId('Check this https://youtu.be/dQw4w9WgXcQ lol'), 'dQw4w9WgXcQ');
    });

    test('handles Shorts, live, music, mobile and bare-domain share links', () {
      const cases = {
        'https://youtube.com/shorts/aqz-KE-bpKQ?si=xyz': 'aqz-KE-bpKQ',
        'https://www.youtube.com/shorts/aqz-KE-bpKQ': 'aqz-KE-bpKQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&feature=share': 'dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=x': 'dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ?si=x': 'dQw4w9WgXcQ',
        'https://youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2': 'dQw4w9WgXcQ',
        'youtu.be/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
        'Watch this: https://youtu.be/dQw4w9WgXcQ?si=Abc123.': 'dQw4w9WgXcQ',
        'dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      };
      cases.forEach((input, id) => expect(LinkParser.youtubeVideoId(input), id, reason: input));
    });

    test('returns null for plain search text', () {
      expect(LinkParser.youtubeVideoId('lofi hip hop beats'), isNull);
    });
  });

  group('Formatters', () {
    test('bytes', () {
      expect(Formatters.bytes(0), '0 B');
      expect(Formatters.bytes(1536), '1.5 KB');
      expect(Formatters.bytes(10 * 1024 * 1024), '10.0 MB');
    });

    test('duration', () {
      expect(Formatters.duration(const Duration(minutes: 3, seconds: 7)), '03:07');
      expect(Formatters.duration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('ago: how YouTube says when a video came out', () {
      final now = DateTime(2026, 11, 18, 12);
      expect(Formatters.ago(now.subtract(const Duration(minutes: 5)), now: now), '5 minutes ago');
      expect(Formatters.ago(now.subtract(const Duration(hours: 1)), now: now), '1 hour ago');
      expect(Formatters.ago(now.subtract(const Duration(days: 2)), now: now), '2 days ago');
      expect(Formatters.ago(now.subtract(const Duration(days: 15)), now: now), '2 weeks ago');
      expect(Formatters.ago(now.subtract(const Duration(days: 95)), now: now), '3 months ago');
      expect(Formatters.ago(now.subtract(const Duration(days: 800)), now: now), '2 years ago');
      expect(Formatters.ago(now.add(const Duration(minutes: 1)), now: now), 'just now', reason: 'clock skew');
    });

    test('fileName strips illegal characters', () {
      expect(Formatters.fileName('a/b:c*d?"e<f>g|h'), 'abcdefgh');
    });
  });
}

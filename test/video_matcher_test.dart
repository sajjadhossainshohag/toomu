import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/video_matcher.dart';

int _s(String title, String author, int sec,
        {String t = 'Espresso', String? a = 'Sabrina Carpenter', int? d = 175}) =>
    VideoMatcher.score(
      title: title,
      author: author,
      duration: Duration(seconds: sec),
      targetTitle: t,
      targetAuthor: a,
      targetDuration: d == null ? null : Duration(seconds: d),
    );

void main() {
  test('exact title + channel + duration is a clear winner', () {
    final scores = [
      _s('Sabrina Carpenter - Espresso (Lyrics)', 'Lyric Vibes', 176),
      _s('Espresso', 'Sabrina Carpenter', 175),
      _s('Espresso (Live)', 'Sabrina Carpenter', 240),
    ];
    expect(VideoMatcher.clearWinner(scores), 1);
  });

  test('ambiguous results ask the user', () {
    final scores = [
      _s('Espresso', 'Sabrina Carpenter', 175),
      _s('Espresso', 'Sabrina Carpenter', 176), // re-upload by same channel
    ];
    expect(VideoMatcher.clearWinner(scores), isNull);
  });

  test('works for non-Latin titles and ignores punctuation', () {
    expect(VideoMatcher.normalize('Mone Koshe | Rakib Musabbir!'), 'mone koshe rakib musabbir');
    expect(VideoMatcher.normalize('দূর না জা — Tanveer'), 'দূর না জা tanveer');
  });

  test('wrong duration is penalised', () {
    expect(_s('Espresso', 'Sabrina Carpenter', 600), lessThan(_s('Espresso', 'Sabrina Carpenter', 175)));
  });
}

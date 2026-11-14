/// Finds which search result is the video YouTube says it is playing, from
/// the media session's title, channel and duration.
abstract class VideoMatcher {
  /// Lower-case letters (with their vowel signs/marks) and digits only;
  /// works for any script (Bangla, Hindi…).
  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ').trim();

  static int score({
    required String title,
    required String author,
    required Duration? duration,
    required String targetTitle,
    String? targetAuthor,
    Duration? targetDuration,
  }) {
    var s = 0;
    final t = normalize(title), tt = normalize(targetTitle);
    if (t == tt) {
      s += 4;
    } else if (t.isNotEmpty && tt.isNotEmpty && (t.contains(tt) || tt.contains(t))) {
      s += 2;
    }
    if (targetAuthor != null && targetAuthor.isNotEmpty) {
      final a = normalize(author), ta = normalize(targetAuthor);
      if (a == ta) {
        s += 3;
      } else if (a.isNotEmpty && ta.isNotEmpty && (a.contains(ta) || ta.contains(a))) {
        s += 1;
      }
    }
    if (duration != null && targetDuration != null && targetDuration > Duration.zero) {
      final diff = (duration - targetDuration).inSeconds.abs();
      if (diff <= 2) {
        s += 3;
      } else if (diff <= 5) {
        s += 1;
      } else if (diff > 10) {
        s -= 3;
      }
    }
    return s;
  }

  /// A score this high means title, channel and/or duration all agree.
  static const confident = 7;

  /// Index of the clear winner in [scores], or null when it's ambiguous.
  static int? clearWinner(List<int> scores) {
    if (scores.isEmpty) return null;
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    if (scores[best] < confident) return null;
    final runnerUp = [for (var i = 0; i < scores.length; i++) if (i != best) scores[i]]
        .fold<int>(-100, (m, v) => v > m ? v : m);
    return runnerUp >= scores[best] - 1 ? null : best;
  }
}

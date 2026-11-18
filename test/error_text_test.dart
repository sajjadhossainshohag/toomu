import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/error_text.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';

DioException _refused(String url, int code) {
  final request = RequestOptions(path: url);
  return DioException(requestOptions: request, response: Response(requestOptions: request, statusCode: code));
}

void main() {
  test('a GitHub rate limit during an update check is not blamed on YouTube', () {
    for (final code in [403, 429]) {
      final text = ErrorText.of(_refused('https://api.github.com/repos/a/b/releases/latest', code));
      expect(text, contains('GitHub'));
      expect(text, isNot(contains('YouTube')));
    }
  });

  test("the downloader's own name and bug-report advice never reach the screen", () {
    final text = ErrorText.of(YtDlpException(
      'ERROR: [youtube] dQw4w9WgXcQ: Video unavailable. This content is not available; please report this issue on '
      ' https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropriate issue template. Confirm you are on '
      'the latest version using  yt-dlp -U',
    ));
    expect(text, 'Video unavailable. This content is not available');
    expect(ErrorText.of(YtDlpException('')), isNot(contains('yt-dlp')));
    expect(ErrorText.of(StateError('yt-dlp exited with code 1')), 'The downloader exited with code 1');
    expect(
      ErrorText.of(StateError('Download failed: HTTP 404 for https://github.com/yt-dlp/yt-dlp/releases/download/x/yt-dlp.exe')),
      'Download failed: HTTP 404',
    );
  });

  test('sign-in problems point to where signing in now is', () {
    for (final m in ['ERROR: [youtube] abcdefghijk: Sign in to confirm your age', 'The provided YouTube account cookies are no longer valid']) {
      final text = ErrorText.of(YtDlpException(m));
      expect(text, isNot(contains('YouTube account')), reason: 'that Settings row is gone');
      expect(text, contains('Sign in'));
    }
  });

  test('only a 403 from YouTube says YouTube refused', () {
    expect(ErrorText.of(_refused('https://rr3---sn-a.googlevideo.com/videoplayback', 403)), contains('YouTube'));
    expect(ErrorText.of(_refused('https://cdn.example.com/movie.mp4', 403)), isNot(contains('YouTube')));
  });
}

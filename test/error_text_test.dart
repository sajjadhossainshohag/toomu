import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/error_text.dart';

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

  test('only a 403 from YouTube says YouTube refused', () {
    expect(ErrorText.of(_refused('https://rr3---sn-a.googlevideo.com/videoplayback', 403)), contains('YouTube'));
    expect(ErrorText.of(_refused('https://cdn.example.com/movie.mp4', 403)), isNot(contains('YouTube')));
  });
}

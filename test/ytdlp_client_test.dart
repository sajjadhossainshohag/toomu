import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/services/ytdlp_service.dart';

YtDlpResult _info(List<Map<String, Object?>> formats) =>
    YtDlpResult(exitCode: 0, out: jsonEncode({'id': 'x', 'formats': formats}), err: '');

void main() {
  test("yt-dlp's default client is tried first", () {
    expect(YtDlpService.clientFallbacks.first, isNull);
  });

  test('lookup with separate video streams is accepted', () {
    final r = _info([
      {'format_id': '137', 'vcodec': 'avc1.640028', 'acodec': 'none', 'height': 1080},
      {'format_id': '140', 'vcodec': 'none', 'acodec': 'mp4a.40.2'},
    ]);
    expect(YtDlpService.hasAdaptiveVideo(r), isTrue);
  });

  test('lookup with only the combined 360p stream is rejected', () {
    final r = _info([
      {'format_id': '18', 'vcodec': 'avc1.42001E', 'acodec': 'mp4a.40.2', 'height': 360},
    ]);
    expect(YtDlpService.hasAdaptiveVideo(r), isFalse);
  });

  test('broken output is rejected', () {
    expect(YtDlpService.hasAdaptiveVideo(const YtDlpResult(exitCode: 0, out: 'nope', err: '')), isFalse);
  });
}

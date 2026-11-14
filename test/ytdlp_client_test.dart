import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/services/ytdlp_service.dart';

YtDlpResult _info(List<Map<String, Object?>> formats) =>
    YtDlpResult(exitCode: 0, out: jsonEncode({'id': 'x', 'formats': formats}), err: '');

void main() {
  test('the JS-free visionOS client is tried first, then yt-dlp\'s default', () {
    expect(YtDlpService.clientFallbacks.take(2), ['visionos', null]);
    // Dead since Aug 2026 (all formats 403).
    expect(YtDlpService.clientFallbacks, isNot(contains('android_vr')));
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

  test('age-restricted videos are not retried with other clients', () {
    const err = 'ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users.';
    expect(YtDlpService.isAgeRestricted(err), isTrue);
    expect(YtDlpService.isRetryable(err), isFalse);
    // The bot check still is.
    expect(YtDlpService.isRetryable("ERROR: Sign in to confirm you're not a bot"), isTrue);
  });
}

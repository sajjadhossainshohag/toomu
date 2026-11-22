import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';

import 'support/download_harness.dart';

/// A download still stopping when a test ends must not run on into the next
/// test, after its services are gone ("SettingsService" not found in
/// "the oldest waiting download starts first").
void main() {
  test('tearing down waits for a download that is slow to stop', () async {
    final h = DownloadHarness();
    await h.setUp();
    h.ytdlp.onRun = (c, _, canceled) async {
      await canceled;
      await Future<void>.delayed(const Duration(milliseconds: 300)); // a slow stop
      return FakeYtDlp.failed('stopped');
    };
    final t = await h.service.enqueueStream(url: 'http://127.0.0.1:9/a.m3u8', title: 'Slow stop', format: 'best');
    await DownloadHarness.until(() => h.ytdlp.calls.isNotEmpty, what: 'yt-dlp to start');
    await h.tearDown();
    expect(t.status.value, DownloadStatus.paused);
  });
}

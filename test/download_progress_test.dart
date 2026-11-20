import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/services/download_service.dart';

DownloadTask _task(DownloadKind kind) => DownloadTask(
      id: '1', title: 't', kind: kind, extension: 'mp4', filePath: '/x.mp4', createdAt: DateTime(2026));

void main() {
  test('aria2c lines: video stage then audio stage add up', () {
    final task = _task(DownloadKind.video);
    var bytes = 0;
    final p = YtDlpProgress(task, (b) => bytes = b);

    p.onLine('[download] Destination: /tmp/x.f137.mp4');
    p.onLine('[#2089b0 25MiB/100MiB(25%) CN:8 DL:5.1MiB ETA:15s]');
    expect(bytes, 25 * 1024 * 1024);
    expect(task.totalBytes.value, 100 * 1024 * 1024);
    expect(task.phase.value, DownloadPhase.video);

    p.onLine('[#2089b0 100MiB/100MiB(100%) CN:8 DL:5.1MiB]');
    p.onLine('[download] Destination: /tmp/x.f140.m4a');
    p.onLine('[#a1b2c3 2.0MiB/4.0MiB(50%) CN:8 DL:1.0MiB ETA:2s]');
    expect(bytes, 102 * 1024 * 1024);
    expect(task.totalBytes.value, 104 * 1024 * 1024);
    expect(task.phase.value, DownloadPhase.audio);

    p.onLine('[Merger] Merging formats into "/x.mp4"');
    expect(task.phase.value, DownloadPhase.merging);
  });

  test('built-in downloader progress template', () {
    final task = _task(DownloadKind.audio);
    var bytes = 0;
    final p = YtDlpProgress(task, (b) => bytes = b);
    p.onLine('[toomu] 140 1048576 4194304 NA 524288.5');
    expect(bytes, 1048576);
    expect(task.totalBytes.value, 4194304);
    p.onLine('[toomu] 140 2097152 NA 4300000 524288.5'); // unknown total → estimate
    expect(bytes, 2097152);
    p.onLine('[ExtractAudio] Destination: /x.mp3');
    expect(task.phase.value, DownloadPhase.converting);
  });

  test('looking up → starting → downloading, first-bytes callback once', () {
    final task = _task(DownloadKind.video)..phase.value = DownloadPhase.lookingUp;
    var firstBytes = 0;
    final p = YtDlpProgress(task, (_) {}, onFirstBytes: () => firstBytes++);

    p.onLine('[youtube] eVli-tstM5E: Downloading webpage');
    expect(task.phase.value, DownloadPhase.lookingUp);
    p.onLine('[info] eVli-tstM5E: Downloading 1 format(s): 137+140');
    expect(task.phase.value, DownloadPhase.starting);
    p.onLine('[download] Destination: /tmp/x.f137.mp4');
    p.onLine('[#2089b0 0B/100MiB(0%) CN:8 DL:0B]');
    expect(task.phase.value, DownloadPhase.starting); // no bytes yet
    p.onLine('[#2089b0 1.0MiB/100MiB(1%) CN:8 DL:1.0MiB]');
    p.onLine('[#2089b0 2.0MiB/100MiB(2%) CN:8 DL:1.0MiB]');
    expect(task.phase.value, DownloadPhase.video);
    expect(firstBytes, 1);
  });

  group('a resumed download counts the part it finished before the pause', () {
    const mib = 1024 * 1024;

    test('aria2c: the audio part adds to the video part yt-dlp already has', () {
      final task = _task(DownloadKind.video);
      var bytes = 0;
      final p = YtDlpProgress(task, (b) => bytes = b);
      // Paused during the audio part; on resume yt-dlp skips the finished
      // video part and reports it without a byte count.
      p.onLine('[download] /tmp/x.f137.mp4 has already been downloaded');
      p.onLine('[toomu] 137 NA 104857600 NA NA finished');
      p.onLine('[download] Destination: /tmp/x.f140.m4a');
      p.onLine('[#a1b2c3 2.0MiB/4.0MiB(50%) CN:8 DL:1.0MiB ETA:2s]');
      expect(bytes, 102 * mib);
      expect(task.totalBytes.value, 104 * mib);
      expect(task.phase.value, DownloadPhase.audio);
    });

    test('built-in downloader: the same', () {
      final task = _task(DownloadKind.video);
      var bytes = 0;
      final p = YtDlpProgress(task, (b) => bytes = b);
      p.onLine('[toomu] 137 NA 104857600 NA NA finished');
      p.onLine('[toomu] 140 2097152 4194304 NA 524288.5 downloading');
      expect(bytes, 102 * mib);
    });

    test("a part finished in this run isn't counted twice", () {
      final task = _task(DownloadKind.video);
      var bytes = 0;
      final p = YtDlpProgress(task, (b) => bytes = b);
      p.onLine('[download] Destination: /tmp/x.f137.mp4');
      p.onLine('[#2089b0 100MiB/100MiB(100%) CN:8 DL:5.1MiB]');
      p.onLine('[toomu] 137 104857600 104857600 NA 5242880 finished');
      expect(bytes, 100 * mib);
      p.onLine('[download] Destination: /tmp/x.f140.m4a');
      p.onLine('[#a1b2c3 2.0MiB/4.0MiB(50%) CN:8 DL:1.0MiB ETA:2s]');
      expect(bytes, 102 * mib);
      expect(task.totalBytes.value, 104 * mib);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';

import 'support/download_harness.dart';

/// The temp-file sweep (run at every start) lists folders a moment after it
/// noted which ones are in use: a download added in between lost its work
/// folder ("PathNotFoundException ... info.json").
void main() {
  late DownloadHarness h;
  setUp(() async {
    h = DownloadHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  test('a download started while temp files are swept keeps its work folder', () async {
    final sweep = h.service.cleanTemporaryFiles();
    // Added right after the sweep began, before it lists the folders.
    final t = DownloadTask(
      id: 'started-now',
      title: 'New',
      kind: DownloadKind.video,
      extension: 'mp4',
      filePath: '${h.root}/Video/New.mp4',
      createdAt: DateTime.now(),
      status: DownloadStatus.paused,
    );
    h.service.tasks.insert(0, t);
    final work = Directory('${h.ytdlp.workRoot}/${t.id}')..createSync(recursive: true);
    await sweep;
    expect(work.existsSync(), isTrue);
  });

  test('the sweep still removes work folders no download owns', () async {
    final orphan = Directory('${h.ytdlp.workRoot}/gone')..createSync(recursive: true);
    await h.service.cleanTemporaryFiles();
    expect(orphan.existsSync(), isFalse);
  });
}

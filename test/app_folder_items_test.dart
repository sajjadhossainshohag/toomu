import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/subtitles.dart';
import 'package:toomu/app/data/providers/local_music_provider.dart';

void main() {
  test('subtitles of a video in the Windows download folder are found, so they move and delete with it', () async {
    final tmp = await Directory.systemTemp.createTemp('toomu_folder_');
    addTearDown(() => tmp.delete(recursive: true));
    final video = await Directory('${tmp.path}/Video').create();
    File('${video.path}/Clip.mp4').writeAsStringSync('v');
    File('${video.path}/Clip.en.srt').writeAsStringSync('s');

    final clip = folderItems(video.path, 'Video').singleWhere((m) => m['name'] == 'Clip.mp4');
    expect(Subtitles.sidecarsOf(clip['path'] as String).map((p) => p.split('/').last), ['Clip.en.srt']);
  });
}

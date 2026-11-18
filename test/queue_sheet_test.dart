import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/track.dart';
import 'package:toomu/app/modules/player/views/widgets/queue_sheet.dart';
import 'package:toomu/app/services/audio_player_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  testWidgets('the next song starting while the queue is open moves the "now playing" mark to it', (tester) async {
    late AudioPlayerService audio;
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('queue_main', dir)));
      Get.put(StorageService(await tempBox('queue_queue', dir)), tag: StorageService.queueBox);
      audio = Get.put(AudioPlayerService());
    });
    addTearDown(Get.reset);
    audio.queue.assignAll([
      for (var i = 0; i < 3; i++) Track(id: 'local:$i', title: 'Song $i', uri: 'file:///m/$i.mp3'),
    ]);
    audio.currentIndex.value = 0;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: QueueSheet()))),
    );
    double markAt() => tester.getCenter(find.byIcon(Icons.graphic_eq_rounded)).dy;
    expect(markAt(), closeTo(tester.getCenter(find.text('Song 0')).dy, 24));

    audio.currentIndex.value = 1; // the song ended, the next one plays
    await tester.pump();
    expect(markAt(), closeTo(tester.getCenter(find.text('Song 1')).dy, 24));
  });
}

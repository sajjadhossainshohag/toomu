import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/services/private_vault.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory tmp;
  late PrivateVault vault;
  late Directory outside;
  late StorageService store;

  setUp(() async {
    tmp = await useTempStorageDir();
    store = StorageService(await tempBox('private_${DateTime.now().microsecondsSinceEpoch}', tmp));
    vault = PrivateVault(await Directory('${tmp.path}/private').create(), store);
    outside = await Directory('${tmp.path}/Download/Toomu/Video').create(recursive: true);
  });
  tearDown(() => deleteTempStorageDir(tmp));

  File make(String name, [String body = 'data']) => File('${outside.path}/$name')..writeAsStringSync(body);

  test('the PIN is checked against a salted hash, never stored as typed', () async {
    expect(vault.hasPin, isFalse);
    expect(vault.checkPin('1234'), isFalse);
    await vault.setPin('1234');
    expect(vault.hasPin, isTrue);
    expect(vault.checkPin('1234'), isTrue);
    expect(vault.checkPin('4321'), isFalse);
  });

  test('a moved video takes its subtitles along, and the original is gone', () async {
    final video = make('Clip.mp4');
    make('Clip.en.srt', 'subs');
    final moved = await vault.moveManyIn([video.path], () async {
      for (final f in outside.listSync()) {
        f.deleteSync();
      }
    });
    expect(moved, [video.path]);
    expect(vault.files().map((f) => f.uri.pathSegments.last), ['Clip.mp4']);
    expect(File('${vault.dir.path}/Clip.en.srt').readAsStringSync(), 'subs');
  });

  test('when the original stays (declined in Android\'s dialog), no copy is left behind', () async {
    final video = make('Clip.mp4');
    expect(await vault.moveManyIn([video.path], () async {}), isEmpty);
    expect(await vault.moveManyIn([video.path], () => throw const FileSystemException('busy')), isEmpty);
    expect(vault.dir.listSync(), isEmpty);
    expect(video.existsSync(), isTrue);
  });

  test('a batch asks to delete once; declined, nothing moves and no copy is left', () async {
    final files = [make('A.mp4'), make('B.mp3'), make('C.pdf')];
    var asked = 0;
    expect(await vault.moveManyIn([for (final f in files) f.path], () async => asked++), isEmpty);
    expect(asked, 1);
    expect(vault.dir.listSync(), isEmpty);
    expect(files.every((f) => f.existsSync()), isTrue);
  });

  test('a batch where only some originals could be deleted counts only those', () async {
    final files = [make('A.mp4'), make('B.mp3'), make('C.pdf')];
    final moved = await vault.moveManyIn([for (final f in files) f.path], () async {
      files[0].deleteSync();
      files[2].deleteSync();
    });
    expect(moved, [files[0].path, files[2].path]);
    expect(vault.files().map((f) => f.uri.pathSegments.last).toSet(), {'A.mp4', 'C.pdf'});
    expect(files[1].existsSync(), isTrue);
  });

  test('a batch that fails while copying leaves no copies and every original in place', () async {
    final files = [make('A.mp4'), make('B.mp3')];
    var asked = false;
    await expectLater(
      vault.moveManyIn([files[0].path, '${outside.path}/missing.mp4', files[1].path], () async => asked = true),
      throwsA(isA<FileSystemException>()),
    );
    expect(asked, isFalse);
    expect(vault.dir.listSync(), isEmpty);
    expect(files.every((f) => f.existsSync()), isTrue);
  });

  test('same names do not overwrite each other, in and out', () async {
    for (var i = 0; i < 2; i++) {
      final f = make('Song.mp3', 'take $i');
      await vault.moveManyIn([f.path], () async => f.deleteSync());
    }
    expect(vault.files().map((f) => f.uri.pathSegments.last).toSet(), {'Song.mp3', 'Song (2).mp3'});

    make('Song.mp3', 'already there');
    final back = await vault.moveOut(File('${vault.dir.path}/Song.mp3'), outside.path);
    expect(back, '${outside.path}/Song (2).mp3');
    expect(File(back).readAsStringSync(), 'take 0');
    expect(vault.files().map((f) => f.uri.pathSegments.last), ['Song (2).mp3']);
  });

  test('files are sorted into video, audio and other', () {
    expect(PrivateVault.kindOf('/a/b.MKV'), DownloadKind.video);
    expect(PrivateVault.kindOf('/a/b.opus'), DownloadKind.audio);
    expect(PrivateVault.kindOf('/a/b.pdf'), DownloadKind.file);
  });

  test('the wrong-PIN lockout survives reopening the private folder, and grows each time', () async {
    var clock = DateTime(2026);
    vault.now = () => clock;
    await vault.setPin('1234');
    Future<void> failAll() async {
      for (var i = 0; i < PrivateVault.maxTries; i++) {
        expect(await vault.tryPin('0000'), isFalse);
      }
    }

    for (var i = 0; i < PrivateVault.maxTries - 1; i++) {
      await vault.tryPin('0000');
    }
    expect(await vault.lockLeft(), Duration.zero);
    vault = PrivateVault(vault.dir, store)..now = () => clock;
    expect(await vault.tryPin('0000'), isFalse);
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0], reason: 'tries made before reopening still count');

    vault = PrivateVault(vault.dir, store)..now = () => clock;
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0]);
    expect(await vault.tryPin('1234'), isFalse, reason: 'even the right PIN waits out the lock');

    clock = clock.add(PrivateVault.lockWaits[0]);
    await failAll();
    expect(await vault.lockLeft(), PrivateVault.lockWaits[1]);

    clock = clock.add(PrivateVault.lockWaits[1]);
    expect(await vault.tryPin('1234'), isTrue);
    await failAll();
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0], reason: 'the right PIN starts over');
  });

  test('subtitles left in the public folder go too once the video is moved', () async {
    final video = make('Clip.mp4');
    final subs = make('Clip.en.srt', 'subs');
    expect(await vault.moveManyIn([video.path], () async => video.deleteSync()), [video.path]);
    expect(subs.existsSync(), isFalse);
    expect(File('${vault.dir.path}/Clip.en.srt').readAsStringSync(), 'subs');
  });

  test('two files with the same name moved at the same time both survive', () async {
    final other = await Directory('${tmp.path}/Music').create();
    final a = make('Song.mp3', 'a');
    final b = File('${other.path}/Song.mp3')..writeAsStringSync('b');
    await Future.wait([
      vault.moveManyIn([a.path], () async => a.deleteSync()),
      vault.moveManyIn([b.path], () async => b.deleteSync()),
    ]);
    expect(vault.files().map((f) => f.readAsStringSync()).toSet(), {'a', 'b'});
  });

  test('setting the clock back during a lockout neither ends it nor stretches it', () async {
    final start = DateTime(2026, 6, 1);
    var clock = start;
    vault.now = () => clock;
    await vault.setPin('1234');
    for (var i = 0; i < PrivateVault.maxTries; i++) {
      await vault.tryPin('0000');
    }
    clock = start.subtract(const Duration(days: 30));
    expect(await vault.tryPin('1234'), isFalse);
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0]);
    clock = clock.add(PrivateVault.lockWaits[0]);
    expect(await vault.tryPin('1234'), isTrue);
  });

  test('moving the phone clock forward does not end the lockout; a restart starts the wait over', () async {
    var wall = DateTime(2026, 6, 1);
    var boot = 7;
    var up = const Duration(hours: 3);
    PrivateVault withClocks() => PrivateVault(vault.dir, store)
      ..now = (() => wall)
      ..uptime = (() async => (boot: boot, elapsed: up));
    vault = withClocks();
    await vault.setPin('1234');
    for (var i = 0; i < PrivateVault.maxTries; i++) {
      await vault.tryPin('0000');
    }
    wall = wall.add(const Duration(days: 1));
    up += const Duration(seconds: 10);
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0] - const Duration(seconds: 10));
    expect(await vault.tryPin('1234'), isFalse);

    boot++;
    up = const Duration(seconds: 5);
    vault = withClocks();
    expect(await vault.lockLeft(), PrivateVault.lockWaits[0], reason: 'uptime starts again with the phone');
    up += PrivateVault.lockWaits[0];
    expect(await vault.tryPin('1234'), isTrue);
  });
}

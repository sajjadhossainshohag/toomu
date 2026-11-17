import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/device_profile.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  group('moving busy data out of the main box', () {
    test('first launch copies the data and keeps the old copy', () async {
      final main = StorageService(await tempBox('main_a', dir));
      await main.write('tasks', [1, 2, 3]);
      await main.write('theme', 'dark');

      final moved = main.split(await tempBox('busy_a', dir), 'tasks');

      expect(moved.read<List>('tasks'), [1, 2, 3]);
      expect(main.read<List>('tasks'), [1, 2, 3], reason: 'removed only once the new box has it on disk');
      expect(main.read<String>('theme'), 'dark');
    });

    test('the next launch drops the old copy and keeps the newer data', () async {
      final main = StorageService(await tempBox('main_b', dir));
      final busy = await tempBox('busy_b', dir);
      await main.write('tasks', [1]);
      await busy.write('tasks', [1, 2]);

      final moved = main.split(busy, 'tasks');

      expect(moved.read<List>('tasks'), [1, 2]);
      expect(main.read<List>('tasks'), isNull);
    });

    test('nothing to move leaves both boxes alone', () async {
      final main = StorageService(await tempBox('main_c', dir));
      final moved = main.split(await tempBox('busy_c', dir), 'tasks');
      expect(moved.read<List>('tasks'), isNull);
    });
  });

  group('low-end phones', () {
    test('little RAM, the system low-RAM flag or Android 8.1 and older', () {
      expect(DeviceProfile.isLowEnd(ramMb: 2048, lowRamFlag: false, sdk: 33), isTrue);
      expect(DeviceProfile.isLowEnd(ramMb: 3072, lowRamFlag: false, sdk: 33), isTrue);
      expect(DeviceProfile.isLowEnd(ramMb: 8192, lowRamFlag: true, sdk: 33), isTrue);
      expect(DeviceProfile.isLowEnd(ramMb: 6144, lowRamFlag: false, sdk: 27), isTrue);
    });

    test('a 4 GB phone on a recent Android is not', () {
      expect(DeviceProfile.isLowEnd(ramMb: 4096, lowRamFlag: false, sdk: 30), isFalse);
      expect(DeviceProfile.isLowEnd(ramMb: 0, lowRamFlag: false, sdk: 34), isFalse);
    });
  });
}

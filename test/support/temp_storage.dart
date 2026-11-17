import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

Future<Directory> useTempStorageDir() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp('toomu_test_');
  // GetStorage asks path_provider for a folder even when given a path.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  return dir;
}

Future<void> deleteTempStorageDir(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Windows: a box file may still be open; the OS cleans its temp folder.
  }
}

Future<GetStorage> tempBox(String name, Directory dir) async {
  final box = GetStorage(name, dir.path);
  await box.initStorage;
  return box;
}

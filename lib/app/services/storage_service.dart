import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// Key-value persistence. Wrapped so it can be replaced (Hive, Isar…) later.
class StorageService extends GetxService {
  static StorageService get to => Get.find();

  final GetStorage _box = GetStorage();

  T? read<T>(String key) => _box.read<T>(key);

  Future<void> write(String key, dynamic value) => _box.write(key, value);

  Future<void> remove(String key) => _box.remove(key);
}

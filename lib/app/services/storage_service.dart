import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// Key-value persistence. Wrapped so it can be replaced (Hive, Isar…) later.
class StorageService extends GetxService {
  StorageService([GetStorage? box]) : _box = box ?? GetStorage();

  static StorageService get to => Get.find();
  static StorageService get logs => Get.find(tag: logsBox);
  static StorageService get downloads => Get.find(tag: downloadsBox);
  static StorageService get positions => Get.find(tag: positionsBox);
  static StorageService get queue => Get.find(tag: queueBox);
  static StorageService get browser => Get.find(tag: browserBox);

  static const logsBox = 'logs';
  static const downloadsBox = 'downloads';
  static const positionsBox = 'positions';
  static const queueBox = 'queue';
  static const browserBox = 'browser';

  /// Browser history: opened when the browser first needs it, not at start-up.
  static const historyBox = 'browser_history';

  static Future<void> init() => Future.wait([
        GetStorage.init(),
        // GetStorage rewrites a box's whole file on every write: data written
        // often gets a file of its own instead of rewriting everything else.
        for (final box in [logsBox, downloadsBox, positionsBox, queueBox, browserBox]) GetStorage.init(box),
      ]);

  final GetStorage _box;

  T? read<T>(String key) => _box.read<T>(key);

  Future<void> write(String key, dynamic value) => _box.write(key, value);

  Future<void> remove(String key) => _box.remove(key);

  StorageService split(GetStorage target, String key) {
    final moved = StorageService(target);
    final old = read<dynamic>(key);
    if (old == null) return moved;
    // GetStorage's write future completes before the file is written, so the
    // old copy goes only on a later launch, once the new box has it on disk.
    if (moved.read<dynamic>(key) == null) {
      moved.write(key, old);
    } else {
      remove(key);
    }
    return moved;
  }
}

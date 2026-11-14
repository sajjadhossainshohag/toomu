import '../../core/values/app_constants.dart';
import '../../services/storage_service.dart';
import '../models/download_task.dart';

/// Persists download history/queue so it survives app restarts.
class DownloadRepository {
  DownloadRepository(this._storage);

  final StorageService _storage;

  List<DownloadTask> load() {
    final raw = _storage.read<List>(AppConstants.kDownloadTasks) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save(Iterable<DownloadTask> tasks) => _storage.write(
        AppConstants.kDownloadTasks,
        tasks.map((t) => t.toJson()).toList(),
      );
}

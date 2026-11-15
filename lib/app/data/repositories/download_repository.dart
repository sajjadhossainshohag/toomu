import 'package:flutter/foundation.dart';

import '../../core/values/app_constants.dart';
import '../../services/storage_service.dart';
import '../models/download_task.dart';

/// Persists download history/queue so it survives app restarts.
class DownloadRepository {
  DownloadRepository(this._storage);

  final StorageService _storage;

  List<DownloadTask> load() {
    final raw = _storage.read<List>(AppConstants.kDownloadTasks) ?? const [];
    final tasks = <DownloadTask>[];
    for (final e in raw.whereType<Map>()) {
      // One unreadable entry must not cost the user the whole list.
      try {
        tasks.add(DownloadTask.fromJson(Map<String, dynamic>.from(e)));
      } catch (err) {
        debugPrint('[Downloads] skipped a saved task: $err');
      }
    }
    return tasks;
  }

  Future<void> save(Iterable<DownloadTask> tasks) => _storage.write(
        AppConstants.kDownloadTasks,
        tasks.map((t) => t.toJson()).toList(),
      );
}

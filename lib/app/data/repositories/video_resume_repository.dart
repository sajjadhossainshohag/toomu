import '../../services/storage_service.dart';

/// Remembers where each video was left off (MX-style resume), keyed by
/// file path/URI. Keeps the most recent [_max] entries.
class VideoResumeRepository {
  VideoResumeRepository._();

  static final VideoResumeRepository instance = VideoResumeRepository._();

  static const storageKey = 'video_positions';
  static const _max = 300;

  /// Positions closer than this to either end aren't worth resuming.
  static const margin = Duration(seconds: 10);

  StorageService get _storage => StorageService.positions;

  Map<String, int> _all() =>
      Map<String, int>.from((_storage.read<Map>(storageKey) ?? const {}).cast<String, int>());

  // Called for every video tile while scrolling: no copy of the whole map.
  Duration? positionOf(String key) {
    final ms = _storage.read<Map>(storageKey)?[key];
    return ms is int ? Duration(milliseconds: ms) : null;
  }

  /// 0..1 watched fraction for list thumbnails, or null if not started.
  double? progressOf(String key, Duration? duration) {
    final p = positionOf(key);
    if (p == null || duration == null || duration.inMilliseconds <= 0) return null;
    return (p.inMilliseconds / duration.inMilliseconds).clamp(0, 1).toDouble();
  }

  Future<void> save(String key, Duration position, Duration duration) async {
    final all = _all()..remove(key);
    final done = duration > Duration.zero && position >= duration - margin;
    if (!done && position > margin) all[key] = position.inMilliseconds;
    while (all.length > _max) {
      all.remove(all.keys.first);
    }
    await _storage.write(storageKey, all);
  }
}

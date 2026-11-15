import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame times over a short window (opening / closing the player), written
/// to the diagnostics log: "[Perf] player open: 21 frames, 2 slow, worst
/// build 41 ms / raster 12 ms". Lag reports then come with numbers.
class FrameProbe {
  FrameProbe._(this.label);

  final String label;
  final _timings = <FrameTiming>[];

  /// Records frames for [window], then logs a summary.
  static void watch(String label, {Duration window = const Duration(milliseconds: 1200)}) {
    final probe = FrameProbe._(label);
    void collect(List<FrameTiming> t) => probe._timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    Future<void>.delayed(window, () {
      SchedulerBinding.instance.removeTimingsCallback(collect);
      debugPrint(summarize(
        label,
        [for (final t in probe._timings) (build: t.buildDuration, raster: t.rasterDuration)],
      ));
    });
  }

  /// A frame is slow when building or drawing it took longer than one
  /// 60 Hz frame (16.7 ms).
  static const budget = Duration(microseconds: 16667);

  @visibleForTesting
  static String summarize(String label, List<({Duration build, Duration raster})> frames) {
    if (frames.isEmpty) return '[Perf] $label: no frames';
    var slow = 0;
    var worstBuild = Duration.zero, worstRaster = Duration.zero;
    for (final f in frames) {
      if (f.build > budget || f.raster > budget) slow++;
      if (f.build > worstBuild) worstBuild = f.build;
      if (f.raster > worstRaster) worstRaster = f.raster;
    }
    return '[Perf] $label: ${frames.length} frames, $slow slow, '
        'worst build ${worstBuild.inMilliseconds} ms / raster ${worstRaster.inMilliseconds} ms';
  }
}

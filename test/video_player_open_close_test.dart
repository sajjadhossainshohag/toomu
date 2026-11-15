import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/core/utils/frame_probe.dart';
import 'package:toomu/app/routes/app_pages.dart';

/// Regression tests for the video player stuttering as it opens / closes.
void main() {
  test('the player opens without a fade (the screen turns as it opens)', () {
    // During a fade the page behind is on screen too, so turning to
    // landscape laid out the whole app again mid-animation.
    final page = AppPages.routes.singleWhere((p) => p.name == Routes.videoPlayer);
    expect(page.transition, Transition.noTransition);
  });

  group('frame probe summary', () {
    ({Duration build, Duration raster}) frame(int buildMs, int rasterMs) =>
        (build: Duration(milliseconds: buildMs), raster: Duration(milliseconds: rasterMs));

    test('counts frames over the 60 Hz budget and the worst times', () {
      expect(
        FrameProbe.summarize('player open', [frame(5, 6), frame(41, 9), frame(8, 25), frame(16, 16)]),
        '[Perf] player open: 4 frames, 2 slow, worst build 41 ms / raster 25 ms',
      );
    });

    test('no frames drawn', () {
      expect(FrameProbe.summarize('player close', const []), '[Perf] player close: no frames');
    });
  });
}

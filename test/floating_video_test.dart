import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/services/video_session_service.dart';
import 'package:toomu/app/widgets/floating_video.dart';

void main() {
  const screen = Size(390, 844);
  const padding = EdgeInsets.only(top: 24, bottom: 16);

  test('the corner video starts bottom right, above the bottom tabs', () {
    final r = FloatingVideo.restRect(screen, padding, left: false);
    expect(r.right, 390 - 12);
    expect(r.bottom, 844 - 16 - 80);
  });

  test('dragged, it lands on the side it is dropped on or flicked toward, and stays on screen', () {
    final dropped = Rect.fromLTWH(40, 300, 179, 100);
    expect(FloatingVideo.landsLeft(dropped, 390, 0), isTrue);
    expect(FloatingVideo.landsLeft(dropped, 390, 1200), isFalse, reason: 'flicked right');

    final high = FloatingVideo.restRect(screen, padding, left: true, top: -200);
    expect(high.left, 12);
    expect(high.top, 24 + 8);
    final low = FloatingVideo.restRect(screen, padding, left: true, top: 5000);
    expect(low.bottom, 844 - 16 - 8);
  });

  testWidgets('corner video is not left in half the box after returning to the app', (tester) async {
    // Hidden, Android takes the video surface away and gives a new one back on return; the old picture
    // widget kept the old layout (video in a corner, the rest blank). Back in the app, it is made afresh.
    Get.put(VideoSessionService());
    addTearDown(Get.reset);
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: FloatingVideo()));
    final state = tester.state<State<FloatingVideo>>(find.byType(FloatingVideo));
    final before = FloatingVideo.surfaceOf(state);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(FloatingVideo.surfaceOf(state), isNot(before));
  });
}

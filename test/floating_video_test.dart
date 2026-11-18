import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

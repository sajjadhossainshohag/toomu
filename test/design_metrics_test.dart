import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/theme/design_metrics.dart';

Future<double> _scaleAt(WidgetTester tester, Size size) async {
  late double scale;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size),
    child: Builder(builder: (context) {
      scale = context.scale;
      return const SizedBox();
    }),
  ));
  return scale;
}

void main() {
  testWidgets('scale is the same in portrait and landscape (no blow-up while rotating)', (tester) async {
    final portrait = await _scaleAt(tester, const Size(393, 852));
    final landscape = await _scaleAt(tester, const Size(852, 393));
    expect(landscape, portrait);
    expect(portrait, closeTo(393 / 375, 0.001));
  });

  testWidgets('scale is clamped for small phones and tablets', (tester) async {
    expect(await _scaleAt(tester, const Size(300, 600)), 0.85);
    expect(await _scaleAt(tester, const Size(800, 1280)), 1.3);
  });
}

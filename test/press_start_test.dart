import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/widgets/press_start.dart';

void main() {
  late int started;

  Future<void> pumpList(WidgetTester tester) async {
    started = 0;
    await tester.pumpWidget(MaterialApp(
      home: ListView(
        children: [
          for (var i = 0; i < 20; i++)
            PressStart(
              onStart: () => started++,
              child: GestureDetector(onTap: () {}, child: SizedBox(height: 120, child: Text('card $i'))),
            ),
        ],
      ),
    ));
  }

  testWidgets('a tap starts the lookup once, before the finger lifts', (tester) async {
    await pumpList(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('card 1')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(started, 1, reason: 'started while the finger is still down');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(started, 1);
  });

  testWidgets('a quick tap shorter than the delay still starts it', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('card 2'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(started, 1);
  });

  testWidgets('scrolling the list starts nothing', (tester) async {
    await pumpList(tester);
    await tester.fling(find.text('card 1'), const Offset(0, -400), 2000);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PressStart).first));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(started, 0);
  });
}

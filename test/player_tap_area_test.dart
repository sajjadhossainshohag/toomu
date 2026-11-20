import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/video_player/views/player_tap_area.dart';

void main() {
  late List<String> events;

  Future<void> pumpArea(WidgetTester tester) async {
    events = [];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 300,
          child: PlayerTapArea(
            onTap: (at) => events.add('tap ${at.dx.round()}'),
            onDoubleTap: (at) => events.add('double ${at.dx.round()}'),
          ),
        ),
      ),
    );
  }

  Future<void> tapAt(WidgetTester tester, double x) async {
    final g = await tester.startGesture(Offset(x, 150));
    await g.up();
  }

  testWidgets('a tap shows the player controls at once, without waiting for a double tap', (tester) async {
    await pumpArea(tester);
    await tapAt(tester, 200);
    await tester.pump(); // the next frame, no waiting
    expect(events, ['tap 200']);
  });

  testWidgets('a double tap on the right still skips forward', (tester) async {
    await pumpArea(tester);
    await tapAt(tester, 350);
    await tester.pump(const Duration(milliseconds: 100));
    await tapAt(tester, 352);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap 350', 'double 352']);
  });

  testWidgets('quick taps after a double tap keep skipping', (tester) async {
    await pumpArea(tester);
    await tapAt(tester, 350);
    await tester.pump(const Duration(milliseconds: 100));
    await tapAt(tester, 350);
    await tester.pump(const Duration(milliseconds: 150));
    await tapAt(tester, 350);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap 350', 'double 350', 'double 350']);
  });

  testWidgets('slow taps are separate taps', (tester) async {
    await pumpArea(tester);
    await tapAt(tester, 200);
    await tester.pump(const Duration(milliseconds: 500));
    await tapAt(tester, 200);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap 200', 'tap 200']);
  });

  testWidgets('taps far apart are not a double tap', (tester) async {
    await pumpArea(tester);
    await tapAt(tester, 30);
    await tester.pump(const Duration(milliseconds: 100));
    await tapAt(tester, 370);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap 30', 'tap 370']);
  });
}

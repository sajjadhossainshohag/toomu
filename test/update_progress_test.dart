import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/widgets/update_progress.dart';

void main() {
  test('update download shows percent and sizes', () {
    expect(UpdateProgress.label(15 << 20, 60 << 20), '25% · 15.0 MB of 60.0 MB');
    expect(UpdateProgress.label(60 << 20, 60 << 20), startsWith('100% · '));
  });

  test('update download before the size is known', () {
    expect(UpdateProgress.label(0, 0), 'Starting…');
    expect(UpdateProgress.label(3 << 20, 0), '3.0 MB');
  });

  testWidgets('the update dialog body shows the percent', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: UpdateProgress(received: 42, total: 100)),
    ));
    expect(find.textContaining('42%'), findsOneWidget);
  });
}

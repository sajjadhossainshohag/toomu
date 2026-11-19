import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/services/update_service.dart';

void main() {
  late UpdateService updates;

  setUp(() {
    Get.testMode = true;
    updates = UpdateService();
    updates.progress.value = 0.3; // an update is downloading
  });
  tearDown(Get.reset);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    updates.showProgress();
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsOneWidget);
  }

  testWidgets('tapping outside the update download does not close it', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsOneWidget);
  });

  testWidgets('Back does not close the update download', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsOneWidget);
  });

  testWidgets('check for updates while one downloads shows its progress, not the update offer again', (tester) async {
    await open(tester);
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsNothing);
    expect(updates.downloading, isTrue); // hiding doesn't stop it

    await updates.checkNow();
    await tester.pumpAndSettle();
    expect(find.text('Downloading update'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
  });
}

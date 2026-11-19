import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/private_folder/controllers/private_folder_controller.dart';
import 'package:toomu/app/routes/app_pages.dart';

void main() {
  setUpAll(() => Get.testMode = true);

  test('the open private folder locks when the Windows window is minimized', () {
    final c = PrivateFolderController()..stage.value = PrivateStage.open;
    c.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(c.stage.value, PrivateStage.open, reason: "the fingerprint prompt makes the app inactive");
    c.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(c.stage.value, PrivateStage.locked);
  });

  test('leaving the app while changing the PIN locks instead of letting anyone set a new one', () {
    final c = PrivateFolderController()..stage.value = PrivateStage.open;
    c.changePin();
    expect(c.stage.value, PrivateStage.create);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(c.stage.value, PrivateStage.locked);
  });

  testWidgets('locking closes the file menu and its actions do nothing', (tester) async {
    addTearDown(Get.reset);
    final c = PrivateFolderController()..stage.value = PrivateStage.open;
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold()),
        GetPage(name: Routes.privateFolder, page: () => const Scaffold(body: Text('private'))),
      ],
    ));
    Get.toNamed<void>(Routes.privateFolder);
    await tester.pumpAndSettle();
    final file = File('${Directory.systemTemp.path}/toomu_lock_test.pdf');
    unawaited(c.showItemMenu(file));
    await tester.pumpAndSettle();
    expect(find.text('Move out of private folder'), findsOneWidget);

    c.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(find.text('Move out of private folder'), findsNothing);
    expect(find.text('private'), findsOneWidget, reason: 'the folder page itself stays, locked');

    unawaited(c.openItem(file));
    await tester.pumpAndSettle();
    expect(find.text('Open in another app?'), findsNothing);
  });
}

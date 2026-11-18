import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/browser/address.dart';
import 'package:toomu/app/modules/browser/controllers/browser_controller.dart';
import 'package:toomu/app/modules/browser/controllers/browser_session.dart';
import 'package:toomu/app/services/browser_store.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

/// The browser's tabs without WebViews: what the session does with them.
void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await deleteTempStorageDir(dir);
  });

  setUp(() async {
    final main = StorageService(await tempBox('session_main_${n++}', dir));
    Get.put(main);
    Get.put(SettingsService().init());
    final history = StorageService(await tempBox('session_history_${n++}', dir));
    Get.put(BrowserStore(main, () async => history));
  });
  tearDown(() {
    // Closing the session (not just forgetting it) cancels its pending save, which would otherwise run after
    // the store is gone.
    Get.delete<BrowserSession>(force: true);
    Get.reset();
  });

  BrowserSession open() => Get.put(BrowserSession());

  DownloadTask task() => DownloadTask(
    id: 't1',
    title: 'Movie',
    kind: DownloadKind.video,
    extension: 'mp4',
    filePath: '/x/Movie.mp4',
    createdAt: DateTime(2026),
    source: DownloadSource.direct,
    url: 'https://cdn.example.com/old.mp4',
    pageUrl: 'https://movies.example.com/avatar',
  );

  test('closing tabs in the tab switcher keeps it open', () async {
    final s = open();
    final a = s.tab;
    final b = s.newTab(url: 'https://b.com/');
    final c = s.newTab(url: 'https://c.com/');
    s.openSwitcher();

    s.close(a); // a tab in the background
    expect(s.showingSwitcher.value, isTrue);
    expect(s.active.value, c, reason: 'the shown tab stays shown');

    s.close(c); // the shown one
    expect(s.showingSwitcher.value, isTrue);
    expect(s.active.value, b);
    await Future<void>.delayed(Duration.zero);
  });

  test('closing the last tab really closes it: the switcher is left empty, no new tab pops up', () async {
    final s = open();
    s.openSwitcher();
    s.close(s.tab);
    expect(s.tabs, isEmpty);
    expect(s.active.value, isNull);
    expect(s.showingSwitcher.value, isTrue);
    expect(await s.handleBack(), isTrue, reason: 'back from the empty switcher leaves the browser');
    await Future<void>.delayed(Duration.zero);
  });

  test('"Close all" leaves no tabs either, and the next visit starts with a new tab', () async {
    final s = open();
    s.newTab(url: 'https://b.com/');
    s.openSwitcher();
    s.closeAll();
    expect(s.tabs, isEmpty);
    expect(s.showingSwitcher.value, isTrue);
    Get.delete<BrowserSession>(force: true); // leaving the browser saves the tabs

    final again = open();
    expect(again.tabs, hasLength(1));
    expect(again.tab.tabUrl, newTabUrl);
    await Future<void>.delayed(Duration.zero);
  });

  test('closing from the page itself does not open the switcher', () async {
    final s = open();
    final b = s.newTab(url: 'https://b.com/');
    s.close(b);
    expect(s.showingSwitcher.value, isFalse);
    await Future<void>.delayed(Duration.zero);
  });

  test('a refresh-link tab opened inside the browser closes alone when done', () async {
    final s = open();
    final page = s.newTab(url: 'https://b.com/');
    final refresh = s.newTab(refreshFor: task());
    expect(s.tabs, contains(refresh));
    refresh.onRefreshed!(); // its link was found
    expect(s.tabs, isNot(contains(refresh)));
    expect(s.tabs, contains(page), reason: 'the other tabs stay; the browser stays open');
    await Future<void>.delayed(Duration.zero);
  });

  test('refresh-link tabs are not brought back next time', () async {
    final s = open();
    s.newTab(url: 'https://b.com/');
    s.newTab(refreshFor: task());
    s.onClose(); // saves the tabs
    final saved = BrowserStore.to.savedTabs;
    expect(saved.tabs.map((t) => t.url), [newTabUrl, 'https://b.com/']);
    expect(saved.active, 1, reason: 'the last kept tab, not the gone refresh tab');
  });

  test('a closed tab\'s "Switch" button does nothing', () async {
    final s = open();
    final b = s.newTab(url: 'https://b.com/');
    final a = s.newTab(url: 'https://a.com/');
    s.close(b);
    s.activate(b); // its "Switch" button, tapped after it closed
    expect(s.active.value, a);
    expect(s.tabs, isNot(contains(b)));
    await Future<void>.delayed(Duration.zero);
  });

  test('tabs get their own controllers even when made at once', () {
    final s = open();
    for (var i = 0; i < 20; i++) {
      s.newTab(url: 'https://site$i.com/');
    }
    expect({for (final t in s.tabs) t.id}, hasLength(s.tabs.length));
    expect(s.tabs.whereType<BrowserController>(), hasLength(21));
  });
}

import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/browser/controllers/browser_session.dart';
import 'package:toomu/app/modules/browser/incognito.dart';
import 'package:toomu/app/services/browser_store.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

/// Incognito tabs: nothing of them is kept once they close.
void main() {
  late Directory dir;
  var n = 0;
  late List<String> ended;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await deleteTempStorageDir(dir);
  });

  setUp(() async {
    final main = StorageService(await tempBox('incognito_main_${n++}', dir));
    Get.put(main);
    Get.put(SettingsService().init());
    final history = StorageService(await tempBox('incognito_history_${n++}', dir));
    Get.put(BrowserStore(main, () async => history));
    ended = [];
    Incognito.onEnd = ended.add;
  });
  tearDown(() {
    Get.delete<BrowserSession>(force: true);
    Get.reset();
    Incognito.onEnd = null;
  });

  BrowserSession open() => Get.put(BrowserSession());

  test('an incognito page is not added to history', () async {
    final s = open();
    final normal = s.newTab(url: 'https://normal.example/');
    final secret = s.newTab(url: 'https://secret.example/', incognito: true);
    await normal.onHistoryChanged(WebUri('https://normal.example/a'));
    await secret.onHistoryChanged(WebUri('https://secret.example/b'));
    await secret.onTitle('Secret page');
    final urls = BrowserStore.to.history.entries.map((v) => v.url);
    expect(urls, contains('https://normal.example/a'));
    expect(urls.where((u) => u.contains('secret')), isEmpty);
  });

  test('incognito tabs are not brought back next time', () async {
    final s = open();
    s.newTab(url: 'https://normal.example/');
    s.newTab(url: 'https://secret.example/', incognito: true);
    await Get.delete<BrowserSession>(force: true); // leaving the browser saves the tabs
    final saved = BrowserStore.to.savedTabs.tabs.map((t) => t.url);
    expect(saved, contains('https://normal.example/'));
    expect(saved.where((u) => u.contains('secret')), isEmpty);
  });

  test('a link opened in a new tab from an incognito tab stays incognito', () {
    final s = open();
    final secret = s.newTab(url: 'https://secret.example/', incognito: true);
    secret.openTab!('https://secret.example/next', background: false);
    expect(s.tab.url.value, 'https://secret.example/next');
    expect(s.tab.incognito, isTrue);
  });

  test("closing the last incognito tab wipes the session's cookies and site data", () {
    final s = open();
    final a = s.newTab(url: 'https://a.example/', incognito: true);
    final b = s.newTab(url: 'https://b.example/', incognito: true);
    final first = Incognito.session;
    s.close(a);
    expect(ended, isEmpty, reason: 'another incognito tab is still open');
    s.close(b);
    expect(ended, [first]);
    // The next incognito tab starts clean, in a new session.
    s.newTab(url: 'https://c.example/', incognito: true);
    expect(Incognito.session, isNot(first));
  });

  test('leaving the browser ends incognito too', () async {
    final s = open();
    s.newTab(url: 'https://a.example/', incognito: true);
    final session = Incognito.session;
    await Get.delete<BrowserSession>(force: true);
    expect(ended, [session]);
  });

  test('close all in the incognito switcher closes only incognito tabs', () {
    final s = open();
    final normal = s.newTab(url: 'https://normal.example/');
    s.newTab(url: 'https://secret.example/', incognito: true);
    s.closeAll(incognito: true);
    expect(s.tabs.where((t) => t.incognito), isEmpty);
    expect(s.tabs, contains(normal));
    expect(ended, hasLength(1));
  });
}

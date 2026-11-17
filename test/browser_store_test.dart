import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/address.dart';
import 'package:toomu/app/services/browser_store.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;
  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  var n = 0;
  Future<StorageService> box() async => StorageService(await tempBox('browser_${n++}', dir));

  /// A store over [main] (tabs, bookmarks) and [history] (its own box).
  BrowserStore store(StorageService main, StorageService history) => BrowserStore(main, () async => history);

  test('history and bookmarks are still there after a restart', () async {
    final main = await box();
    final hist = await box();
    final a = store(main, hist);
    await a.loadHistory();
    a
      ..visit('https://a.com/', '')
      ..retitle('https://a.com/', 'Alpha')
      ..toggleBookmark('https://b.com/', 'Beta');
    a.onClose(); // app closing: the pending history write happens now

    final b = store(main, hist);
    await b.loadHistory();
    expect(b.history.entries.single.title, 'Alpha');
    expect(b.bookmarks.has('https://b.com'), isTrue);
  });

  test('history lives in its own box: saving tabs never rewrites it', () async {
    final main = await box();
    final hist = await box();
    final s = store(main, hist);
    await s.loadHistory();
    s.visit('https://a.com/', 'A');
    s.onClose();
    s.saveTabs([(url: 'https://a.com/', title: 'A')], 0);
    expect(main.read<dynamic>('history'), isNull);
    expect(hist.read<List<dynamic>>('history'), hasLength(1));
    expect(hist.read<dynamic>('tabs'), isNull);
  });

  test('history is not read until the browser needs it', () async {
    var opened = 0;
    final hist = await box();
    final s = BrowserStore(await box(), () async {
      opened++;
      return hist;
    });
    s.savedTabs;
    s.bookmarks.items;
    expect(opened, 0);
    await Future.wait([s.loadHistory(), s.loadHistory()]);
    expect(opened, 1, reason: 'read once');
  });

  test('pages visited while history is still loading are kept, newest first', () async {
    final hist = await box();
    await hist.write('history', [
      {'u': 'https://old.com/', 't': 'Old', 'a': 1000},
    ]);
    final gate = Completer<void>();
    final s = BrowserStore(await box(), () async {
      await gate.future;
      return hist;
    });
    s.visit('https://new.com/', 'New'); // starts the load
    s.onClose(); // nothing may be written over the saved history yet
    expect(hist.read<List<dynamic>>('history'), hasLength(1));
    gate.complete();
    await s.loadHistory();
    expect(s.history.entries.map((v) => v.title), ['New', 'Old']);
    s.onClose();
    expect(hist.read<List<dynamic>>('history'), hasLength(2));
  });

  test('history is written once for a burst of page events, not on each', () async {
    final hist = await box();
    final s = store(await box(), hist);
    await s.loadHistory();
    final before = s.historyVersion.value;
    s
      ..visit('https://a.com/', '')
      ..retitle('https://a.com/', 'A')
      ..retitle('https://a.com/', 'A'); // unchanged: nothing to do
    expect(hist.read<List<dynamic>>('history'), isNull, reason: 'not yet: waits for the burst to end');
    expect(s.historyVersion.value, before + 2, reason: 'screens update at once, but not for no change');
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(hist.read<List<dynamic>>('history'), hasLength(1));
  });

  test('clearing history waits for it to load, so nothing comes back', () async {
    final hist = await box();
    await hist.write('history', [
      {'u': 'https://old.com/', 't': 'Old', 'a': 1000},
    ]);
    final s = store(await box(), hist);
    await s.clearHistory();
    await Future<void>.delayed(Duration.zero);
    expect(s.history.entries, isEmpty);
    expect(hist.read<List<dynamic>>('history'), isEmpty);
  });

  test('open tabs and the shown one come back next time', () async {
    final main = await box();
    store(main, await box()).saveTabs([(url: 'https://a.com/', title: 'A'), (url: newTabUrl, title: 'New tab')], 1);
    final back = store(main, await box()).savedTabs;
    expect(back.tabs.map((t) => t.url), ['https://a.com/', newTabUrl]);
    expect(back.tabs.first.title, 'A');
    expect(back.active, 1);
  });

  test('first time: no saved tabs', () async {
    final saved = store(await box(), await box()).savedTabs;
    expect(saved.tabs, isEmpty);
  });

  test('find in page counter', () {
    expect(findCount(2, 5), '2/5');
    expect(findCount(0, 0), '0/0');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/tab_session.dart';

void main() {
  group('opening tabs', () {
    test('"New tab" goes at the end and is shown', () {
      final s = TabSession()
        ..open('a')
        ..open('b');
      expect(s.ids, ['a', 'b']);
      expect(s.activeId, 'b');
    });

    test('a link opened in a new tab goes right after its page, in the background', () {
      final s = TabSession()
        ..open('a')
        ..open('b')
        ..activate('a')
        ..open('a1', opener: 'a', background: true);
      expect(s.ids, ['a', 'a1', 'b']);
      expect(s.activeId, 'a', reason: 'you stay on the page');
      expect(s.isLive('a1'), isFalse, reason: 'it loads when shown');
    });

    test('several links from one page keep the order they were opened in', () {
      final s = TabSession()
        ..open('a')
        ..open('b')
        ..activate('a')
        ..open('a1', opener: 'a', background: true)
        ..open('a2', opener: 'a', background: true);
      expect(s.ids, ['a', 'a1', 'a2', 'b']);
    });
  });

  group('memory', () {
    test('only the last few shown tabs keep their page; older ones are dropped', () {
      final s = TabSession(maxLive: 2);
      s.open('a');
      s.open('b');
      final dropped = s.open('c');
      expect(dropped, ['a']);
      expect(s.isLive('a'), isFalse);
      expect(s.isLive('b'), isTrue);
      expect(s.isLive('c'), isTrue);
    });

    test('showing a tab again counts as recent use', () {
      final s = TabSession(maxLive: 2)
        ..open('a')
        ..open('b')
        ..activate('a');
      expect(s.open('c'), ['b']);
    });

    test('the shown tab is never dropped', () {
      final s = TabSession(maxLive: 1)
        ..open('a')
        ..open('b');
      expect(s.isLive('b'), isTrue);
      expect(s.isLive('a'), isFalse);
    });
  });

  group('closing', () {
    test('closing the shown tab goes back to the page that opened it', () {
      final s = TabSession()
        ..open('a')
        ..open('b')
        ..activate('a')
        ..open('a1', opener: 'a');
      expect(s.close('a1'), 'a');
      expect(s.ids, ['a', 'b']);
    });

    test('else to the tab on its left, or the first one', () {
      final s = TabSession()
        ..open('a')
        ..open('b')
        ..open('c');
      expect(s.close('c'), 'b');
      s.activate('a');
      expect(s.close('a'), 'b');
    });

    test('a tab remembers the page that opened it, until that page is closed', () {
      final s = TabSession()
        ..open('a')
        ..open('a1', opener: 'a');
      expect(s.openerOf('a1'), 'a');
      expect(s.openerOf('a'), isNull);
      s.close('a');
      expect(s.openerOf('a1'), isNull);
    });

    test('closing a tab in the background keeps the shown one', () {
      final s = TabSession()
        ..open('a')
        ..open('b');
      expect(s.close('a'), 'b');
      expect(s.activeId, 'b');
    });

    test('closing the last tab leaves none', () {
      final s = TabSession()..open('a');
      expect(s.close('a'), isNull);
      expect(s.length, 0);
      expect(s.activeIndex, -1);
    });

    test('close all', () {
      final s = TabSession()
        ..open('a')
        ..open('b')
        ..closeAll();
      expect(s.ids, isEmpty);
      expect(s.activeId, isNull);
    });
  });

  test('tabs from the last session come back without loading', () {
    final s = TabSession()..restore(['x', 'y']);
    expect(s.ids, ['x', 'y']);
    expect(s.isLive('x') || s.isLive('y'), isFalse);
    s.activate('y');
    expect(s.isLive('y'), isTrue);
  });

  group('restoring tabs', () {
    test('past the limit, the newest tabs come back, not the oldest', () {
      final saved = [for (var i = 1; i <= 33; i++) 'tab$i'];
      final r = newestTabs(saved, 32, 30); // tab33 opened last, tab32 shown
      expect(r.tabs.first, 'tab4');
      expect(r.tabs.last, 'tab33', reason: 'the tab just opened is kept');
      expect(r.tabs[r.active], 'tab33', reason: 'and it is still the one shown');
    });

    test('the shown tab stays the shown tab', () {
      final saved = [for (var i = 1; i <= 33; i++) 'tab$i'];
      final r = newestTabs(saved, 31, 30);
      expect(r.tabs[r.active], 'tab32');
    });

    test('a shown tab that was dropped falls back to the oldest kept one', () {
      final r = newestTabs(['a', 'b', 'c'], 0, 2);
      expect(r.tabs, ['b', 'c']);
      expect(r.tabs[r.active], 'b');
    });

    test('under the limit nothing is dropped; none saved gives none', () {
      final r = newestTabs(['a', 'b'], 1, 30);
      expect(r.tabs, ['a', 'b']);
      expect(r.active, 1);
      expect(newestTabs(<String>[], -1, 30).tabs, isEmpty);
    });
  });

  test('tabs made in the same instant still get different ids', () {
    final now = DateTime(2026, 11, 17);
    final ids = {for (var i = 0; i < 1000; i++) newTabId(now)};
    expect(ids, hasLength(1000));
  });
}

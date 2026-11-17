import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/ad_blocker.dart';
import 'package:toomu/app/modules/browser/media_button.dart';

void main() {
  group('ad-hiding script', () {
    tearDown(forgetAdHidingJs);

    test('every tab gets the same script, built once', () {
      final css = 'x' * 1000;
      final a = adHidingJsFor({'b.com', 'a.com'}, genericCss: css);
      final b = adHidingJsFor({'a.com', 'b.com'}, genericCss: css);
      expect(identical(a, b), isTrue, reason: 'one shared string, not a ~0.5 MB copy per tab');
      expect(a, adHidingJs({'a.com', 'b.com'}, genericCss: css));
    });

    test('a newly allowed site or a new filter list builds it again', () {
      final css = 'x' * 1000;
      final a = adHidingJsFor({'a.com'}, genericCss: css);
      expect(identical(adHidingJsFor({'a.com', 'c.com'}, genericCss: css), a), isFalse);
      expect(adHidingJsFor({'a.com'}, genericCss: 'y' * 1000), contains('y' * 1000));
    });

    test('closing the browser lets it go', () {
      final css = 'x' * 1000;
      final a = adHidingJsFor({}, genericCss: css);
      forgetAdHidingJs();
      expect(identical(adHidingJsFor({}, genericCss: css), a), isFalse);
    });
  });

  group('top bar while scrolling', () {
    test('the page jumping when the bar hides is not the reader scrolling back', () {
      final h = ScrollHider()..update(0);
      expect(h.update(300), isFalse, reason: 'reading down: the bar hides');
      // The bar went away: the page grew and, at its bottom, the scroll
      // position dropped by the bar's height.
      h.rebase(250);
      expect(h.update(270), isFalse, reason: 'still reading down: stays hidden');
      expect(h.update(200), isTrue, reason: 'a real scroll back up shows it');
    });

    test('without re-anchoring, that jump alone would show the bar again (the flicker)', () {
      final h = ScrollHider()..update(0);
      expect(h.update(300), isFalse);
      expect(h.update(250), isTrue);
    });
  });
}

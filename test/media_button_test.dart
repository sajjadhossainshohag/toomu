import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/media_button.dart';

/// The browser's media button moved from a big pill in the middle of the
/// page (covering sites' own buttons) to a corner button that steps aside
/// while reading.
void main() {
  group('mode', () {
    test('supported page → Download, whatever was caught', () {
      expect(mediaButtonMode(supportedPage: true, found: 3, canScan: true), MediaButtonMode.download);
    });

    test('caught media → found (with count)', () {
      expect(mediaButtonMode(supportedPage: false, found: 2, canScan: true), MediaButtonMode.found);
      expect(mediaButtonMode(supportedPage: false, found: 2, canScan: false), MediaButtonMode.found);
    });

    test('nothing yet → the small scan button, or none where pages can\'t be read', () {
      expect(mediaButtonMode(supportedPage: false, found: 0, canScan: true), MediaButtonMode.scan);
      expect(mediaButtonMode(supportedPage: false, found: 0, canScan: false), MediaButtonMode.hidden);
    });
  });

  group('scroll hiding', () {
    test('slides away scrolling down, back scrolling up', () {
      final h = ScrollHider();
      expect(h.update(300), isFalse); // read down the page
      expect(h.update(900), isFalse);
      expect(h.update(860), isTrue); // turned back up
      expect(h.update(1400), isFalse);
    });

    test('small jitters don\'t make it flicker', () {
      final h = ScrollHider()..update(500); // hidden
      expect(h.update(490), isFalse);
      expect(h.update(500), isFalse);
      expect(h.update(480), isFalse);
      expect(h.update(450), isTrue); // a real turn (more than 24 px up from 500)
    });

    test('a turn is measured from where the scroll changed direction', () {
      final h = ScrollHider()..update(500);
      h.update(2000); // deep down, hidden
      expect(h.update(1990), isFalse);
      expect(h.update(1970), isTrue); // 30 px up from 2000, not from 500
    });

    test('always shown near the top, and on a new page', () {
      final h = ScrollHider()..update(800);
      expect(h.update(40), isTrue);
      h.update(800);
      h.reset();
      expect(h.visible, isTrue);
      expect(h.update(50), isTrue); // new page, still near the top
      expect(h.update(300), isFalse); // reading down it
    });
  });
}

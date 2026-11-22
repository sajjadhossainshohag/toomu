import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/address.dart';

void main() {
  test('Desktop site on Facebook leaves the mobile site (m.facebook.com stayed mobile)', () {
    expect(desktopAddress('https://m.facebook.com/watch/?v=123'), 'https://www.facebook.com/watch/?v=123');
    expect(desktopAddress('https://mobile.facebook.com/groups/1'), 'https://www.facebook.com/groups/1');
    expect(desktopAddress('https://touch.facebook.com/'), 'https://www.facebook.com/');
  });

  test('other mobile hosts get their desktop host', () {
    expect(desktopAddress('https://en.m.wikipedia.org/wiki/Dhaka'), 'https://en.wikipedia.org/wiki/Dhaka');
    expect(desktopAddress('https://m.youtube.com/watch?v=x'), 'https://www.youtube.com/watch?v=x');
  });

  test('desktop hosts and local pages are left alone', () {
    expect(desktopAddress('https://www.facebook.com/'), isNull);
    expect(desktopAddress('https://example.com/m.html'), isNull);
    expect(desktopAddress('https://m.co/'), isNull); // the whole site is "m.co"
    expect(desktopAddress('toomu://newtab'), isNull);
  });
}

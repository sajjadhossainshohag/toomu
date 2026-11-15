import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/ad_blocker.dart';
import 'package:toomu/app/modules/browser/filter_engine.dart';

void main() {
  const listed = {'doubleclick.net', 'googlesyndication.com', 'ads.example-cdn.com'};
  bool isListed(String host) {
    var h = host;
    while (true) {
      if (listed.contains(h)) return true;
      final dot = h.indexOf('.');
      if (dot < 0) return false;
      h = h.substring(dot + 1);
    }
  }

  var allowed = <String>{};
  final blocker = AdBlocker(isListed: isListed, allowedSites: () => allowed, filters: () => null);
  setUp(() => allowed = {});

  bool blocks(String request, String page) => blocker.blocks(Uri.parse(request), pageUrl: page);

  group('requests', () {
    test('ad hosts on the list are blocked, subdomains included', () {
      expect(blocks('https://securepubads.g.doubleclick.net/tag/js/gpt.js', 'https://news.site.com/a'), isTrue);
      expect(blocks('https://pagead2.googlesyndication.com/pagead/show_ads.js', 'https://blog.org/'), isTrue);
    });

    test('hosts not on the list load', () {
      expect(blocks('https://cdn.jsdelivr.net/npm/x.js', 'https://news.site.com/'), isFalse);
      expect(blocks('https://i.ytimg.com/vi/x/hq.jpg', 'https://m.youtube.com/'), isFalse);
    });

    test("the page's own site is never blocked, even when listed", () {
      // Visiting a listed site on purpose: its own files still load.
      expect(blocks('https://static.doubleclick.net/app.js', 'https://www.doubleclick.net/'), isFalse);
    });

    test('nothing is blocked on a site the user allowed ads on', () {
      allowed = {'site.com'};
      expect(blocks('https://securepubads.g.doubleclick.net/gpt.js', 'https://news.site.com/a'), isFalse);
      expect(blocks('https://securepubads.g.doubleclick.net/gpt.js', 'https://other.com/'), isTrue);
    });

    test('only web requests are judged', () {
      expect(blocks('data:text/plain,doubleclick.net', 'https://site.com/'), isFalse);
      expect(blocks('blob:https://doubleclick.net/1', 'https://site.com/'), isFalse);
    });
  });

  test('site of a page', () {
    expect(AdBlocker.siteOf('https://news.bbc.co.uk/x'), 'bbc.co.uk');
    expect(AdBlocker.siteOf('https://m.youtube.com/watch?v=1'), 'youtube.com');
    expect(AdBlocker.siteOf('not a url'), '');
  });

  group('ad-hiding script', () {
    test('hides the common ad boxes', () {
      final js = adHidingJs(const {});
      for (final s in ['ins.adsbygoogle', 'div-gpt-ad', 'amp-ad']) {
        expect(js, contains(s));
      }
      expect(js, contains('display:none!important'));
    });

    test('skips allowed sites, safely quoted', () {
      final js = adHidingJs({'site.com', "o'brien.org"});
      expect(js, contains('var allowed = ["o\'brien.org","site.com"];'));
    });
  });

  group('with EasyList', () {
    final easylist = FilterEngine.parse([
      '/ads/banner',
      r'||widgets.net^$script',
      '@@||ads.example-cdn.com/consent.js',
      r'@@||trusted.org^$document',
      'site.com##.sponsor',
      '##.ad-box',
    ].join('\n'));
    final withList = AdBlocker(isListed: isListed, allowedSites: () => allowed, filters: () => easylist);
    bool blocks(String request, String page, {ResourceType? type}) =>
        withList.blocks(Uri.parse(request), pageUrl: page, type: type);

    test('EasyList patterns block first-party ad paths too', () {
      expect(blocks('https://news.site.com/ads/banner1.gif', 'https://news.site.com/'), isTrue);
    });

    test('request kinds come into it', () {
      expect(blocks('https://widgets.net/w.js', 'https://site.com/', type: ResourceType.script), isTrue);
      expect(blocks('https://widgets.net/logo.png', 'https://site.com/', type: ResourceType.image), isFalse);
    });

    test('an EasyList exception beats the hosts list', () {
      expect(blocks('https://ads.example-cdn.com/consent.js', 'https://site.com/'), isFalse);
      expect(blocks('https://ads.example-cdn.com/ad.js', 'https://site.com/'), isTrue);
    });

    test('nothing is blocked on a page EasyList allows', () {
      expect(blocks('https://securepubads.g.doubleclick.net/gpt.js', 'https://www.trusted.org/'), isFalse);
    });

    test('hiding: the site\'s rules, none where the user allowed ads', () {
      final h = withList.hidingFor('https://news.site.com/', pageUrl: 'https://news.site.com/');
      expect(h.generic, isTrue);
      expect(h.css, contains('.sponsor'));
      allowed = {'site.com'};
      final off = withList.hidingFor('https://news.site.com/', pageUrl: 'https://news.site.com/');
      expect(off.generic, isFalse);
      expect(off.css, isEmpty);
    });

    test('the general stylesheet is put in the page script', () {
      expect(adHidingJs(const {}, genericCss: easylist.genericCss), contains('.ad-box{display:none!important}'));
    });
  });

  test('request kind from the file ending or Accept header', () {
    ResourceType? type(String url, [Map<String, String>? headers]) => AdBlocker.typeOf(Uri.parse(url), headers);
    expect(type('https://x.com/a/app.min.js?v=2'), ResourceType.script);
    expect(type('https://x.com/i/pic.WEBP'), ResourceType.image);
    expect(type('https://x.com/f.woff2'), ResourceType.font);
    expect(type('https://x.com/style', {'Accept': 'text/css,*/*;q=0.1'}), ResourceType.stylesheet);
    expect(type('https://x.com/pixel', {'accept': 'image/avif,image/webp'}), ResourceType.image);
    expect(type('https://x.com/frame', {'Accept': 'text/html,application/xhtml+xml'}), ResourceType.subdocument);
    expect(type('https://x.com/api/v1.0/items'), isNull);
    expect(type('https://x.com/api'), isNull);
  });
}

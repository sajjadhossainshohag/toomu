import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/filter_engine.dart';

void main() {
  const page = 'https://news.site.com/article';

  FilterEngine engine(String rules) => FilterEngine.parse(rules);

  bool? decide(FilterEngine e, String url, {String pageUrl = page, bool thirdParty = true, ResourceType? type}) =>
      e.decide(url, pageUrl: pageUrl, thirdParty: thirdParty, type: type);

  group('URL patterns', () {
    test('|| matches the domain and its subdomains, not look-alikes', () {
      final e = engine('||ads.example.com^');
      expect(decide(e, 'https://ads.example.com/x.js'), isTrue);
      expect(decide(e, 'https://cdn.ads.example.com/x.js'), isTrue);
      expect(decide(e, 'https://badads.example.com/x.js'), isNull);
      expect(decide(e, 'https://ads.example.com.evil.net/x.js'), isNull);
    });

    test('^ is a separator, * anything, | an anchor', () {
      final e = engine('/banner/*/ad_\n|https://track.\nswf|\n.com/ads^');
      expect(decide(e, 'https://x.com/banner/728/ad_1.gif'), isTrue);
      expect(decide(e, 'https://track.example.org/p'), isTrue);
      expect(decide(e, 'https://cdn.x.org/https://track.y'), isNull);
      expect(decide(e, 'https://x.org/movie.swf'), isTrue);
      expect(decide(e, 'https://x.org/movie.swf?x=1'), isNull);
      expect(decide(e, 'https://x.com/ads?id=1'), isTrue);
      expect(decide(e, 'https://x.com/adserver'), isNull);
    });

    test('URLs are matched ignoring case unless \$match-case', () {
      expect(decide(engine('/AdBanner.'), 'https://x.com/adbanner.png'), isTrue);
      expect(decide(engine(r'/AdBanner.$match-case'), 'https://x.com/adbanner.png'), isNull);
      expect(decide(engine(r'/AdBanner.$match-case'), 'https://x.com/AdBanner.png'), isTrue);
    });
  });

  group('options', () {
    test('\$third-party / ~third-party', () {
      final e = engine('||cdn.net/ad.js\$third-party\n||site.com/own-ad.js\$~third-party');
      expect(decide(e, 'https://cdn.net/ad.js', thirdParty: true), isTrue);
      expect(decide(e, 'https://cdn.net/ad.js', thirdParty: false), isNull);
      expect(decide(e, 'https://site.com/own-ad.js', thirdParty: false), isTrue);
      expect(decide(e, 'https://site.com/own-ad.js', thirdParty: true), isNull);
    });

    test('\$domain= limits the pages a filter works on', () {
      final e = engine(r'/promo.js$domain=site.com|~shop.site.com');
      expect(decide(e, 'https://cdn.x/promo.js'), isTrue); // news.site.com
      expect(decide(e, 'https://cdn.x/promo.js', pageUrl: 'https://shop.site.com/'), isNull);
      expect(decide(e, 'https://cdn.x/promo.js', pageUrl: 'https://other.org/'), isNull);
    });

    test('request kinds: \$script only blocks scripts (unknown kinds still are)', () {
      final e = engine(r'||widgets.net^$script');
      expect(decide(e, 'https://widgets.net/w.js', type: ResourceType.script), isTrue);
      expect(decide(e, 'https://widgets.net/logo.png', type: ResourceType.image), isNull);
      expect(decide(e, 'https://widgets.net/w', type: null), isTrue);
      final not = engine(r'||widgets.net^$~image');
      expect(decide(not, 'https://widgets.net/logo.png', type: ResourceType.image), isNull);
      expect(decide(not, 'https://widgets.net/w.js', type: ResourceType.script), isTrue);
    });

    test('filters with options it can\'t honour are skipped, not half-applied', () {
      final e = engine(r'||pop.net^$popup' '\n' r'||x.net^$csp=script-src' '\n' r'||y.net^$rewrite=abp-resource:blank-js');
      expect(decide(e, 'https://pop.net/'), isNull);
      expect(decide(e, 'https://x.net/a'), isNull);
      expect(decide(e, 'https://y.net/a.js'), isNull);
    });

    test('regex filters and over-broad patterns are skipped', () {
      final e = engine('/^https:\\/\\/[a-z]+\\.ads\\//\n*\nad\n||a^');
      expect(decide(e, 'https://x.ads/1'), isNull);
      expect(decide(e, 'https://load.com/ad'), isNull);
    });
  });

  group('exceptions', () {
    test('@@ allows what a block filter matched', () {
      final e = engine('||ads.example.com^\n@@||ads.example.com/consent.js');
      expect(decide(e, 'https://ads.example.com/consent.js'), isFalse);
      expect(decide(e, 'https://ads.example.com/banner.js'), isTrue);
    });

    test('@@…\$document turns everything off on that page', () {
      final e = engine('||ads.example.com^\n@@||trusted.org^\$document');
      expect(e.pageAllowed('https://www.trusted.org/page'), isTrue);
      expect(e.pageAllowed(page), isFalse);
      expect(e.hidingFor('https://www.trusted.org/').generic, isFalse);
    });

    test('a block filter with \$document is ignored (would block the page)', () {
      expect(engine(r'||site.com^$document').pageAllowed(page), isFalse);
      expect(decide(engine(r'||site.com^$document'), 'https://site.com/x.js'), isNull);
    });

    test('@@…\$generichide keeps site rules, drops the general stylesheet', () {
      final e = engine('##.ad\nsite.com##.sponsor\n@@||site.com^\$generichide');
      final h = e.hidingFor(page);
      expect(h.generic, isFalse);
      expect(h.css, contains('.sponsor'));
    });

    test('@@…\$elemhide drops all hiding', () {
      final h = engine('##.ad\nsite.com##.sponsor\n@@||site.com^\$elemhide').hidingFor(page);
      expect(h.generic, isFalse);
      expect(h.css, isEmpty);
    });
  });

  group('element hiding', () {
    test('general rules form one stylesheet, one rule per selector', () {
      final e = engine('##.ad-box\n###top-banner\n##div[id^="ad-"]');
      expect(e.genericCss.split('\n'), [
        '.ad-box{display:none!important}',
        '#top-banner{display:none!important}',
        'div[id^="ad-"]{display:none!important}',
      ]);
    });

    test('site rules apply on the site and its subdomains only', () {
      final e = engine('site.com##.sponsor\nother.org##.promo');
      expect(e.hidingFor(page).css, '.sponsor{display:none!important}');
      expect(e.hidingFor('https://other.org/').css, '.promo{display:none!important}');
      expect(e.hidingFor('https://elsewhere.net/').css, isEmpty);
    });

    test('#@# exceptions: general ones leave the stylesheet, site ones the site', () {
      final e = engine('##.ad\n##.banner\n#@#.banner\nsite.com#@#.ad\nsite.com##.ad');
      expect(e.genericCss, isNot(contains('.banner')));
      expect(e.hidingFor(page).css, isEmpty);
      expect(e.hidingFor('https://other.org/').css, isEmpty);
    });

    test('general rules except some sites (~site.com##)', () {
      final e = engine('~site.com##.native-ad');
      expect(e.genericCss, isEmpty);
      expect(e.hidingFor(page).css, isEmpty);
      expect(e.hidingFor('https://other.org/').css, contains('.native-ad'));
    });

    test('extended selectors and snippets are skipped', () {
      final e = engine('site.com#?#div:-abp-has(.ad)\nsite.com##div:has-text(Sponsored)\n'
          'site.com#\$#json-prune ads\nsite.com##+js(nowebrtc)\nsite.com#%#//scriptlet');
      expect(e.hidingFor(page).css, isEmpty);
      expect(decide(e, 'https://site.com/x'), isNull);
    });
  });

  test('pattern → regular expression', () {
    expect(NetworkFilter.toRegex('||a.com^'), r'^[a-z][a-z0-9+.-]*://(?:[^/?#]*\.)?a\.com(?:[^\w\-.%]|$)');
    expect(NetworkFilter.toRegex('|http://x*y|'), r'^http://x.*y$');
  });
}

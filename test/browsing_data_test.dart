import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/address.dart';
import 'package:toomu/app/modules/browser/browsing_data.dart';
import 'package:toomu/app/modules/browser/engine_notice.dart';
import 'package:toomu/app/modules/browser/link_menu.dart';

void main() {
  final t0 = DateTime(2026, 11, 17, 15, 0);

  group('history', () {
    test('newest first; a reload soon after is one visit, not two', () {
      final h = BrowsingHistory()
        ..visit('https://a.com/', 'A', t0)
        ..visit('https://b.com/', 'B', t0.add(const Duration(minutes: 1)))
        ..visit('https://b.com', 'B again', t0.add(const Duration(minutes: 2)));
      expect(h.entries.map((v) => v.title), ['B again', 'A']);
    });

    test('a return after half an hour is a new visit', () {
      final h = BrowsingHistory()
        ..visit('https://a.com/', 'A', t0)
        ..visit('https://a.com/', 'A', t0.add(const Duration(minutes: 31)));
      expect(h.entries, hasLength(2));
    });

    test('the new-tab page and data: links are not remembered', () {
      final h = BrowsingHistory()
        ..visit(newTabUrl, '', t0)
        ..visit('data:text/html,hi', '', t0)
        ..visit('about:blank', '', t0);
      expect(h.entries, isEmpty);
    });

    test('a title that arrives later fills in the visit', () {
      final h = BrowsingHistory()
        ..visit('https://a.com/x', '', t0)
        ..retitle('https://a.com/x', 'Page X');
      expect(h.entries.single.title, 'Page X');
    });

    test('keeps at most its cap, dropping the oldest', () {
      final h = BrowsingHistory(const [], 3);
      for (var i = 0; i < 5; i++) {
        h.visit('https://s$i.com/', '$i', t0.add(Duration(hours: i)));
      }
      expect(h.entries.map((v) => v.title), ['4', '3', '2']);
    });

    test('search matches every word in the title or address', () {
      final h = BrowsingHistory()
        ..visit('https://movielinkbd.at/avatar', 'Avatar The Last Airbender', t0)
        ..visit('https://news.com/', 'News', t0.add(const Duration(hours: 1)));
      expect(h.search('avatar airbender').single.title, 'Avatar The Last Airbender');
      expect(h.search('movielinkbd').single.title, 'Avatar The Last Airbender');
      expect(h.search(''), hasLength(2));
    });

    test('grouped by Today, Yesterday and the date', () {
      final h = BrowsingHistory()
        ..visit('https://old.com/', 'old', DateTime(2025, 3, 2, 9))
        ..visit('https://c.com/', 'c', DateTime(2026, 11, 10, 9))
        ..visit('https://b.com/', 'b', DateTime(2026, 11, 16, 23))
        ..visit('https://a.com/', 'a', DateTime(2026, 11, 17, 1));
      final groups = h.byDay(h.entries, t0);
      expect(groups.map((g) => g.label), ['Today', 'Yesterday', 'Nov 10', 'Mar 2, 2025']);
    });

    test('most visited: one tile per site, busiest first', () {
      final h = BrowsingHistory();
      var t = t0;
      void at(String url) => h.visit(url, url, t = t.add(const Duration(hours: 1)));
      at('https://www.youtube.com/watch?v=1');
      at('https://m.youtube.com/watch?v=2');
      at('https://news.com/');
      at('https://youtube.com/');
      expect(h.mostVisited(5).map((v) => Uri.parse(v.url).host), ['youtube.com', 'news.com']);
      expect(h.mostVisited(1), hasLength(1));
    });

    test('suggestions: addresses starting with what was typed come first, each page once', () {
      final h = BrowsingHistory();
      var t = t0;
      void at(String url, String title) => h.visit(url, title, t = t.add(const Duration(hours: 1)));
      at('https://mymovies.com/', 'Movies blog');
      at('https://movielinkbd.at/', 'MovieLinkBD');
      at('https://movielinkbd.at/', 'MovieLinkBD');
      final s = h.suggest('movie', 5);
      expect(s.map((v) => v.bare), ['movielinkbd.at', 'mymovies.com']);
    });

    test('saved and read back', () {
      final v = PageVisit(url: 'https://a.com/', title: 'A', at: t0);
      final back = PageVisit.fromJson(v.toJson());
      expect((back.url, back.title, back.at), (v.url, v.title, v.at));
    });
  });

  group('bookmarks', () {
    test('the star toggles; www and a trailing slash are the same page', () {
      final b = Bookmarks();
      expect(b.toggle('https://www.a.com/', 'A', t0), isTrue);
      expect(b.has('https://a.com'), isTrue);
      expect(b.toggle('https://a.com', 'A', t0), isFalse);
      expect(b.items, isEmpty);
    });

    test('only web pages can be starred', () {
      expect(Bookmarks().toggle(newTabUrl, '', t0), isFalse);
    });

    test('search by title or address', () {
      final b = Bookmarks()
        ..toggle('https://a.com/', 'Alpha', t0)
        ..toggle('https://b.com/', 'Beta', t0);
      expect(b.search('alp').single.title, 'Alpha');
      expect(b.search('b.com').single.title, 'Beta');
    });
  });

  group('address bar', () {
    test('shows just the site while not typing, like Chrome', () {
      expect(displayAddress('https://www.n5pa.movielinkbd.at/series/avatar?x=1'), 'n5pa.movielinkbd.at');
      expect(displayAddress('http://www.example.com/'), 'example.com');
      expect(displayAddress(newTabUrl), '');
      expect(displayAddress('data:text/html,x'), 'data:text/html,x');
    });

    test('addresses open; words search', () {
      expect(addressTarget('example.com'), 'https://example.com');
      expect(addressTarget('http://x.org/a'), 'http://x.org/a');
      expect(addressTarget('192.168.0.1:8080/admin'), 'https://192.168.0.1:8080/admin');
      expect(addressTarget('avatar last airbender'), 'https://www.google.com/search?q=avatar+last+airbender');
      expect(addressTarget('node.js'), 'https://node.js', reason: 'host-like text is an address');
      expect(addressTarget('hello'), 'https://www.google.com/search?q=hello');
    });

    test('on YouTube, words search YouTube', () {
      expect(
        addressTarget('lofi', currentUrl: 'https://m.youtube.com/'),
        'https://m.youtube.com/results?search_query=lofi',
      );
    });

    test('a Google results page shows its search words', () {
      expect(searchQueryOf('https://www.google.com/search?q=avatar+2024&sca=1'), 'avatar 2024');
      expect(searchQueryOf('https://example.com/search?q=x'), isNull);
    });

    test('Google\'s suggestion answer is read; anything else gives none', () {
      expect(
        parseGoogleSuggest([
          'ava',
          ['avatar', 'avatar 2', ''],
        ]),
        ['avatar', 'avatar 2'],
      );
      expect(parseGoogleSuggest({'x': 1}), isEmpty);
      expect(parseGoogleSuggest(null), isEmpty);
    });

    test('suggestions: what you typed, then bookmarks and history, then searches', () {
      final s = mergeSuggestions(
        'ava',
        bookmarks: [PageVisit(url: 'https://avatar.com/', title: 'Avatar site', at: t0)],
        history: [
          PageVisit(url: 'https://www.avatar.com', title: 'dup', at: t0),
          PageVisit(url: 'https://ava.org/', title: 'Ava', at: t0),
        ],
        searches: ['ava', 'avatar', 'avatar 2'],
      );
      expect(s.map((x) => x.kind), [
        SuggestionKind.typed,
        SuggestionKind.bookmark,
        SuggestionKind.history,
        SuggestionKind.search,
        SuggestionKind.search,
      ]);
      expect(s[0].url, 'https://www.google.com/search?q=ava');
      expect(s.map((x) => x.text).skip(1), ['avatar.com', 'ava.org', 'avatar', 'avatar 2']);
    });

    test('nothing typed: no suggestions', () {
      expect(mergeSuggestions('  ', searches: ['x']), isEmpty);
    });
  });

  group('link menu', () {
    test('web links get Chrome\'s actions', () {
      const l = PageLink(href: 'https://a.com/x', text: 'Read more');
      expect(linkActions(l), [
        LinkAction.openNewTab,
        LinkAction.openIncognito,
        LinkAction.copyAddress,
        LinkAction.copyText,
        LinkAction.download,
        LinkAction.share,
      ]);
      expect(l.title, 'Read more');
    });

    test('in an incognito tab a new tab is already incognito: no second "open" item', () {
      const l = PageLink(href: 'https://a.com/x');
      expect(linkActions(l, incognito: true), isNot(contains(LinkAction.openIncognito)));
      expect(linkActions(l, incognito: true).first, LinkAction.openNewTab);
    });

    test('mail and phone links can only be copied or shared; no text, no "Copy link text"', () {
      expect(linkActions(const PageLink(href: 'mailto:a@b.c')), [LinkAction.copyAddress, LinkAction.share]);
      expect(const PageLink(href: 'mailto:a@b.c').title, 'mailto:a@b.c');
    });
  });

  group('old web engine notice', () {
    test('Android 7–9: a page failing for a non-network reason explains why', () {
      final n = outdatedEngineNotice(
        androidSdk: 24,
        webViewVersion: '119.0.6045.193',
        errorType: 'FAILED_SSL_HANDSHAKE',
      );
      expect(n, contains('Android 7.0'));
      expect(n, contains('Chrome 119'));
      expect(outdatedEngineNotice(androidSdk: 28, webViewVersion: '', errorType: 'UNKNOWN'), contains('Android 9'));
    });

    test('no notice when offline: that is the network, not the engine', () {
      for (final e in ['HOST_LOOKUP', 'TIMEOUT', 'CANCELLED', 'NOT_CONNECTED_TO_INTERNET']) {
        expect(
          outdatedEngineNotice(androidSdk: 25, webViewVersion: '119', errorType: e),
          isNull,
          reason: e,
        );
      }
    });

    test('no notice on Android 10 and newer, or off Android', () {
      expect(outdatedEngineNotice(androidSdk: 29, webViewVersion: '131', errorType: 'UNKNOWN'), isNull);
      expect(outdatedEngineNotice(androidSdk: 0, webViewVersion: '', errorType: 'UNKNOWN'), isNull);
    });
  });

  group('worked out once, not on every key press or page', () {
    test('most visited is cached, and recomputed after any change', () {
      final h = BrowsingHistory();
      var t = t0;
      void at(String url, String title) => h.visit(url, title, t = t.add(const Duration(hours: 1)));
      at('https://a.com/', 'A');
      final first = h.mostVisited(8);
      expect(identical(h.mostVisited(8), first), isTrue, reason: 'cached while nothing changed');

      at('https://b.com/', 'B');
      at('https://b.com/x', 'B2');
      expect(h.mostVisited(8).map((v) => v.site), ['b.com', 'a.com'], reason: 'a visit');

      h.retitle('https://b.com/x', 'B renamed');
      expect(h.mostVisited(8).first.title, 'B renamed', reason: 'a new title');

      h.remove(h.entries.first);
      h.remove(h.entries.first);
      expect(h.mostVisited(8).map((v) => v.site), ['a.com'], reason: 'removed visits');

      h.clear();
      expect(h.mostVisited(8), isEmpty, reason: 'cleared');
    });

    test('a different count is not served from the cache', () {
      final h = BrowsingHistory()
        ..visit('https://a.com/', 'A', t0)
        ..visit('https://b.com/', 'B', t0.add(const Duration(hours: 1)));
      expect(h.mostVisited(1), hasLength(1));
      expect(h.mostVisited(2), hasLength(2));
    });

    test('nothing to record: no change (no save, no rebuild)', () {
      final h = BrowsingHistory()..visit('https://a.com/', 'A', t0);
      expect(h.visit(newTabUrl, '', t0), isFalse);
      expect(h.retitle('https://a.com/', 'A'), isFalse, reason: 'same title');
      expect(h.retitle('https://other.com/', 'X'), isFalse, reason: 'not the latest page');
      expect(h.retitle('https://a.com/', 'A2'), isTrue);
    });

    test('suggestions stop early once enough addresses start with the text, in order', () {
      final h = BrowsingHistory();
      var t = t0;
      for (final u in ['https://zz-movie.com/', 'https://movie1.com/', 'https://movie2.com/', 'https://movie3.com/']) {
        h.visit(u, '', t = t.add(const Duration(hours: 1)));
      }
      expect(h.suggest('movie', 2).map((v) => v.bare), ['movie3.com', 'movie2.com']);
      expect(h.suggest('movie', 5).map((v) => v.bare), ['movie3.com', 'movie2.com', 'movie1.com', 'zz-movie.com']);
    });

    test('a visit\'s matching forms are the same as computing them fresh', () {
      final v = PageVisit(url: 'https://www.m.example.com/Page/', title: 'Hello World', at: t0);
      expect(v.bare, bareUrl(v.url));
      expect(v.site, 'm.example.com');
      expect(PageVisit(url: 'https://m.youtube.com/watch', title: '', at: t0).site, 'youtube.com');
      expect(v.searchText, 'hello world m.example.com/page');
    });
  });
}

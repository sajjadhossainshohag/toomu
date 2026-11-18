import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/modules/browser/redirect_guard.dart';

void main() {
  test('site of a host', () {
    expect(RedirectGuard.siteOf('m.youtube.com'), 'youtube.com');
    expect(RedirectGuard.siteOf('www.bbc.co.uk'), 'bbc.co.uk');
    expect(RedirectGuard.siteOf('news.example.com.bd'), 'example.com.bd');
    expect(RedirectGuard.siteOf('www.abc.to'), 'abc.to');
    expect(RedirectGuard.siteOf('example.com'), 'example.com');
    expect(RedirectGuard.siteOf('192.168.1.10'), '192.168.1.10');
  });

  test('parses hosts files, adblock domain rules and plain lists', () {
    final hosts = Blocklist.parse('''
# comment
127.0.0.1 localhost
0.0.0.0 0.0.0.0
0.0.0.0 ads.example.com # inline comment
||bet.example.net^
||tracker.example.org^\$third-party
plain.example.io
! adblock comment
example.com/path
''');
    expect(hosts, {'ads.example.com', 'bet.example.net', 'plain.example.io'});
  });

  test('closing the browser frees the blocklist', () {
    Blocklist.hosts = {'bet.example'};
    Blocklist.forget();
    expect(Blocklist.contains('bet.example'), isFalse);
  });

  test('a listed host blocks its subdomains', () {
    Blocklist.hosts = {'bet.example'};
    expect(Blocklist.contains('bet.example'), isTrue);
    expect(Blocklist.contains('www.Bet.example'), isTrue);
    expect(Blocklist.contains('notbet.example'), isFalse);
    Blocklist.hosts = const {};
  });

  group('navigation', () {
    final t0 = DateTime(2026);
    RedirectGuard guard({Set<String> listed = const {}}) =>
        RedirectGuard(isListed: (h) => listed.any((l) => h == l || h.endsWith('.$l')));
    bool blocks(RedirectGuard g, String to, {bool redirect = false, Duration after = const Duration(seconds: 1)}) =>
        g.blocks(from: 'https://movies.example/watch/1', to: Uri.parse(to), redirect: redirect, now: t0.add(after));

    test('same site is always allowed', () {
      final g = guard(listed: {'movies.example'})..onTap('');
      expect(blocks(g, 'https://www.movies.example/watch/2'), isFalse);
    });

    test('a jump to another site right after a tap elsewhere is blocked', () {
      final g = guard();
      g.onTap('https://movies.example/watch/2');
      expect(g.blocks(from: 'https://movies.example/', to: Uri.parse('https://bet.example/'), now: DateTime.now()), isTrue);
      g.onTap('');
      expect(g.blocks(from: 'https://movies.example/', to: Uri.parse('https://bet.example/'), now: DateTime.now()), isTrue);
    });

    test('the link the user tapped is allowed, also via its server redirects', () {
      final g = guard()..onTap('https://files.example/get/1');
      expect(g.blocks(from: 'https://movies.example/', to: Uri.parse('https://cdn.files.example/x'), now: DateTime.now()), isFalse);
      expect(g.blocks(from: 'https://movies.example/', to: Uri.parse('https://mirror.example/x'), redirect: true, now: DateTime.now()), isFalse);
    });

    test('without a recent tap only listed hosts are blocked', () {
      final g = guard(listed: {'bet.example'});
      expect(blocks(g, 'https://accounts.example/login'), isFalse);
      expect(blocks(g, 'https://www.bet.example/'), isTrue);
      expect(blocks(g, 'https://www.bet.example/', redirect: true), isTrue);
    });

    test('a tap stops counting after a few seconds', () {
      final g = guard()..onTap('');
      expect(g.blocks(from: 'https://movies.example/', to: Uri.parse('https://other.example/'), now: DateTime.now().add(const Duration(seconds: 5))), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/error_text.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/modules/settings/views/youtube_sign_in_page.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:toomu/app/services/ytdlp_service.dart';

void main() {
  test('the session is saved as a Netscape cookie file yt-dlp reads', () {
    final text = YoutubeAccountService.netscapeCookies(
      [('SAPISID', 'abc/def'), ('__Secure-3PAPISID', 'x=y'), ('__Host-GAPS', 'h'), ('BAD', 'a\tb'), ('', 'z')],
      expires: DateTime.utc(2027, 1, 1),
    );
    final lines = text.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    expect(text, startsWith('# Netscape HTTP Cookie File'));
    expect(lines, hasLength(3), reason: 'values with tabs and nameless cookies are skipped');
    expect(lines[0].split('\t'), ['.youtube.com', 'TRUE', '/', 'TRUE', '1798761600', 'SAPISID', 'abc/def']);
    expect(lines[1].split('\t').sublist(5), ['__Secure-3PAPISID', 'x=y']);
    expect(lines[2].split('\t').take(2), ['www.youtube.com', 'FALSE'], reason: '__Host- cookies are host-only');
  });

  test('sign-in uses a regular Chrome identity (no WebView marker)', () {
    const webView = 'Mozilla/5.0 (Linux; Android 16; ELI-AN00 Build/HONORELI; wv) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.63 Mobile Safari/537.36';
    final agent = YoutubeSignInPage.chromeAgent(webView);
    expect(agent, isNot(contains('; wv')));
    expect(agent, isNot(contains('Version/4.0')));
    expect(agent, contains('Chrome/138.0.0.0 Mobile Safari'));
  });

  test('expired sign-in is recognised and explained', () {
    const err = 'ERROR: [youtube] abc: The provided YouTube account cookies are no longer valid. '
        'They have likely been rotated in the browser as a security measure.';
    expect(YtDlpService.isSessionExpired(err), isTrue);
    expect(ErrorText.of(YtDlpException(err)), contains('sign-in has expired'));
    expect(ErrorText.of(YtDlpException('ERROR: [youtube] abc: Sign in to confirm your age.')),
        contains('the button at the top of Settings'));
  });
}

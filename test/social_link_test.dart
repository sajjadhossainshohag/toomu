import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/link_parser.dart';

void main() {
  test('Instagram and Facebook video links are found in shared text', () {
    expect(LinkParser.socialVideo('look https://www.instagram.com/reel/C8abc12/?igsh=x).'),
        'https://www.instagram.com/reel/C8abc12/?igsh=x');
    expect(LinkParser.socialVideo('https://instagram.com/p/C8abc12/'), 'https://instagram.com/p/C8abc12/');
    expect(LinkParser.socialVideo('https://www.facebook.com/reel/123456'), 'https://www.facebook.com/reel/123456');
    expect(LinkParser.socialVideo('https://m.facebook.com/someone/videos/123456/'),
        'https://m.facebook.com/someone/videos/123456/');
    expect(LinkParser.socialVideo('https://www.facebook.com/watch/?v=123456'), 'https://www.facebook.com/watch/?v=123456');
    expect(LinkParser.socialVideo('https://www.facebook.com/share/v/1AbCd/'), 'https://www.facebook.com/share/v/1AbCd/');
    expect(LinkParser.socialVideo('https://fb.watch/abc123/'), 'https://fb.watch/abc123/');
  });

  test('profiles, other pages and other sites are not video links', () {
    expect(LinkParser.socialVideo('https://www.instagram.com/someone/'), isNull);
    expect(LinkParser.socialVideo('https://www.facebook.com/someone'), isNull);
    expect(LinkParser.socialVideo('https://notfacebook.com/reel/1'), isNull);
    expect(LinkParser.socialVideo('https://youtu.be/dQw4w9WgXcQ'), isNull);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/tiktok_item.dart';
import 'package:toomu/app/services/tiktok_service.dart';

Map<String, dynamic> _item(String id, {Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'desc': 'Caption $id',
      'video': {'playAddr': 'https://v16.tiktok.com/$id.mp4', 'cover': 'c'},
      'author': {'uniqueId': 'user$id', 'nickname': 'User $id'},
      ...extra,
    };

void main() {
  test('videos are read from TikTok data; slideshows and author-less items are not', () {
    final list = [
      _item('1'),
      _item('4', extra: {'imagePost': {'images': []}}),
      _item('5', extra: {'author': {'nickname': 'no username'}}),
      _item('6'),
    ];
    final items = [for (final j in list) TiktokItem.fromJson(j)].whereType<TiktokItem>().toList();
    expect(items.map((i) => i.id), ['1', '6']);
    final first = items.first;
    expect(first.webUrl, 'https://www.tiktok.com/@user1/video/1');
    expect(first.caption, 'Caption 1');
    expect(first.coverUrl, 'c');
  });

  test('a video page is read from its embedded data', () {
    final data = {
      '__DEFAULT_SCOPE__': {
        'webapp.video-detail': {
          'itemInfo': {'itemStruct': _item('42')}
        }
      }
    };
    final html = '<html><script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">'
        '${jsonEncode(data)}</script></html>';
    expect(TiktokService.parseVideoPage(html)?.id, '42');
    expect(TiktokService.parseVideoPage('<html></html>'), isNull);
  });

  test('TikTok links are found in shared text', () {
    expect(TiktokService.linkIn('wow https://vm.tiktok.com/ZMabc123/ lol'), 'https://vm.tiktok.com/ZMabc123/');
    expect(TiktokService.linkIn('https://www.tiktok.com/@a/video/1।'), 'https://www.tiktok.com/@a/video/1');
    expect(TiktokService.linkIn('https://youtu.be/dQw4w9WgXcQ'), isNull);
  });

  test('a link TikTok gives no details for still downloads (yt-dlp reads it)', () {
    final long = TiktokService.bareItem('https://www.tiktok.com/@scout2015/video/6718335390845095173?is_from_webapp=1');
    expect(long?.id, '6718335390845095173');
    expect(long?.webUrl, 'https://www.tiktok.com/@scout2015/video/6718335390845095173');
    final short = TiktokService.bareItem('https://vt.tiktok.com/ZSabc12/', original: 'https://vt.tiktok.com/ZSabc12/');
    expect(short?.webUrl, 'https://vt.tiktok.com/ZSabc12/');
    expect(TiktokService.bareItem('https://www.tiktok.com/foryou'), isNull);
  });

  test("TikTok's firewall check page is recognised", () {
    const waf = '<!DOCTYPE html><html><head><script id="slardar-config" type="application/json">'
        '{"slardarClient": "SlardarWAF"}</script></head><body>Please wait...'
        '<p id="wci" class="_wafchallengeid"></p></body></html>';
    expect(TiktokService.isFirewallPage(waf), isTrue);
    expect(TiktokService.parseVideoPage(waf), isNull);
    expect(TiktokService.isFirewallPage('<html>a normal page</html>'), isFalse);
  });
}

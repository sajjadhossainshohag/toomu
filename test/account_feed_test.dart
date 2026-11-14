import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube/account_feed.dart';
import 'package:toomu/app/services/youtube_account_service.dart';

void main() {
  final feed = AccountFeed(() async => const {});

  test('signed-in headers carry the SAPISIDHASH authorisations', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final h = AccountFeed.headersFor(
      {'SAPISID': 'sap', '__Secure-1PAPISID': 'one', '__Secure-3PAPISID': 'three', 'LOGIN_INFO': 'x'},
      now: at,
    );
    String expected(String sid) => '1700000000_${sha1.convert(utf8.encode('1700000000 $sid https://www.youtube.com'))}';
    expect(h['Authorization'],
        'SAPISIDHASH ${expected('sap')} SAPISID1PHASH ${expected('one')} SAPISID3PHASH ${expected('three')}');
    expect(h['Cookie'], contains('LOGIN_INFO=x'));
    expect(h['X-Youtube-Bootstrap-Logged-In'], 'true');
  });

  test('home page: videos (both formats), chips and the next-page token', () {
    final json = {
      'header': {
        'feedFilterChipBarRenderer': {
          'contents': [
            {'chipCloudChipRenderer': {'text': {'runs': [{'text': 'All'}]}, 'isSelected': true}},
            {
              'chipCloudChipRenderer': {
                'text': {'runs': [{'text': 'Music'}]},
                'navigationEndpoint': {'continuationCommand': {'token': 'MUSIC'}},
              }
            },
          ]
        }
      },
      'contents': [
        {
          'richItemRenderer': {
            'content': {
              'videoRenderer': {
                'videoId': 'aaaaaaaaaaa',
                'title': {'runs': [{'text': 'Old format'}]},
                'ownerText': {
                  'runs': [
                    {'text': 'Chan', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UC1OR2YNQLZJYFdQjFrPWvVw'}}}
                  ]
                },
                'lengthText': {'simpleText': '1:02:03'},
                'viewCountText': {'simpleText': '12,345 views'},
                'publishedTimeText': {'simpleText': '3 days ago'},
              }
            }
          }
        },
        {'richItemRenderer': {'content': {'videoRenderer': {'videoId': 'livelivelive', 'title': {'simpleText': 'Live'}}}}},
        {
          'richItemRenderer': {
            'content': {
              'lockupViewModel': {'contentId': 'PLxyz', 'contentType': 'LOCKUP_CONTENT_TYPE_PLAYLIST'}
            }
          }
        },
        {
          'continuationItemRenderer': {
            'continuationEndpoint': {
              'commandExecutorCommand': {
                'commands': [
                  {'continuationCommand': {'token': 'NEXT'}}
                ]
              }
            }
          }
        },
      ],
    };
    final page = AccountFeed.parse(feed, json, withChips: true);
    expect(page.videos.map((v) => v.id.value), ['aaaaaaaaaaa'], reason: 'live stream and playlist skipped');
    final v = page.videos.single;
    expect(v.title, 'Old format');
    expect(v.author, 'Chan');
    expect(v.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(v.engagement.viewCount, 12345);
    expect(page.chips.map((c) => (c.label, c.token)), [('Music', 'MUSIC')], reason: '"All" is Home itself');
  });

  test('numbers in YouTube text', () {
    expect(AccountFeed.parseViews('1.2M views'), 1200000);
    expect(AccountFeed.parseViews('2.5B'), 2500000000);
    expect(AccountFeed.parseViews('No views'), 0);
    expect(AccountFeed.parseDuration('LIVE'), isNull);
    expect(AccountFeed.parseDuration('4:04'), const Duration(minutes: 4, seconds: 4));
  });

  test('the saved session is read back, including yt-dlp\'s HttpOnly marks', () {
    const file = '# Netscape HTTP Cookie File\n'
        '.youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tabc\n'
        '#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\tlog\n'
        '.google.com\tTRUE\t/\tTRUE\t0\tNID\tother\n';
    expect(YoutubeAccountService.parseNetscapeCookies(file), {'SAPISID': 'abc', 'LOGIN_INFO': 'log'});
  });
}

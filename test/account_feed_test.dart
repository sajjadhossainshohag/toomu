import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube/account_feed.dart';
import 'package:toomu/app/services/youtube_account_service.dart';

void main() {
  final feed = AccountFeed(() async => const {});

  test('Watch later: a playlist\'s items, with views and age from their one info line', () {
    final page = AccountFeed.parse(feed, {
      'contents': [
        {
          'playlistVideoRenderer': {
            'videoId': 'abcdefghijk',
            'title': {'runs': [{'text': 'Saved for later'}]},
            'shortBylineText': {
              'runs': [
                {
                  'text': 'Some Channel',
                  'navigationEndpoint': {'browseEndpoint': {'browseId': 'UC${'c' * 22}'}},
                }
              ]
            },
            'lengthText': {'simpleText': '12:34'},
            'videoInfo': {
              'runs': [{'text': '1.2M views'}, {'text': ' • '}, {'text': '3 years ago'}]
            },
          }
        },
      ],
    });
    final v = page.videos.single;
    expect(v.id.value, 'abcdefghijk');
    expect(v.title, 'Saved for later');
    expect(v.author, 'Some Channel');
    expect(v.channelId.value, 'UC${'c' * 22}');
    expect(v.duration, const Duration(minutes: 12, seconds: 34));
    expect(v.engagement.viewCount, 1200000);
    expect(v.uploadDateRaw, '3 years ago');
  });

  test('Watch later changes: YouTube\'s edit_playlist actions on the WL playlist', () {
    expect(AccountFeed.editWatchLaterBody('abcdefghijk', add: true), {
      'playlistId': 'WL',
      'actions': [{'action': 'ACTION_ADD_VIDEO', 'addedVideoId': 'abcdefghijk'}],
    });
    expect(AccountFeed.editWatchLaterBody('abcdefghijk', add: false), {
      'playlistId': 'WL',
      'actions': [{'action': 'ACTION_REMOVE_VIDEO_BY_VIDEO_ID', 'removedVideoId': 'abcdefghijk'}],
    });
  });

  test('watched report: the player\'s playback-stats link with ver=2 and a playback nonce', () {
    final url = AccountFeed.watchedUrl({
      'playbackTracking': {
        'videostatsPlaybackUrl': {'baseUrl': 'https://s.youtube.com/api/stats/playback?docid=abcdefghijk&ei=E'},
      },
    }, 'NONCE');
    expect(url!.host, 's.youtube.com');
    expect(url.queryParameters, {'docid': 'abcdefghijk', 'ei': 'E', 'ver': '2', 'cpn': 'NONCE'});
    expect(AccountFeed.watchedUrl({'playabilityStatus': {}}, 'NONCE'), isNull);
  });

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

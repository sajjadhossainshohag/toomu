import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// A channel's Videos tab as YouTube sends it today: "lockupViewModel" items with one metadata row
// (views, age; a collaboration lists its channels first).
Map<String, dynamic> _lockup(String id, String title, List<String> row, String length) => {
  'richItemRenderer': {
    'content': {
      'lockupViewModel': {
        'contentImage': {
          'thumbnailViewModel': {
            'overlays': [
              {
                'thumbnailBottomOverlayViewModel': {
                  'badges': [
                    {'thumbnailBadgeViewModel': {'text': length}},
                  ],
                },
              },
            ],
          },
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': title},
            'metadata': {
              'contentMetadataViewModel': {
                'metadataRows': [
                  {
                    'metadataParts': [
                      for (final p in row) {'text': {'content': p}},
                    ],
                  },
                ],
              },
            },
          },
        },
        'contentId': id,
        'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
      },
    },
  },
};

Map<String, dynamic> _more(String token) => {
  'continuationItemRenderer': {
    'continuationEndpoint': {
      'continuationCommand': {'token': token},
    },
  },
};

final _firstPage = {
  'metadata': {
    'channelMetadataRenderer': {'title': 'Sarkar Films'},
  },
  'contents': {
    'twoColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'selected': true,
            'content': {
              'richGridRenderer': {
                'contents': [
                  _lockup('aaaaaaaaaaa', 'Best of Imran & Porshi', ['18K', '17h ago'], '1:02:03'),
                  _lockup('bbbbbbbbbbb', 'Duet', ['Sarkar Films', 'and Imran', '20K', '5d ago'], '4:05'),
                  _more('page2'),
                ],
              },
            },
          },
        },
      ],
    },
  },
};

final _secondPage = {
  'onResponseReceivedActions': [
    {
      'appendContinuationItemsAction': {
        'continuationItems': [
          _lockup('ccccccccccc', 'Best of Porshi', ['1.2M', '2 years ago'], '58:00'),
        ],
      },
    },
  ],
};

class _FakeYoutube extends YoutubeHttpClient {
  final asked = <String>[];

  @override
  Future<String> getString(dynamic url, {Map<String, String> headers = const {}, bool validate = true}) async {
    asked.add('$url');
    return '<html><script>var ytInitialData = ${jsonEncode(_firstPage)};</script></html>';
  }

  @override
  Future<Map<String, dynamic>> sendContinuation(String action, String token, {Map<String, String>? headers}) async {
    asked.add('$action $token');
    return _secondPage;
  }
}

void main() {
  test("a channel's videos show their titles and lengths, not blank rows with 00:00", () async {
    final http = _FakeYoutube();
    final page = await YoutubeProvider(http: http)
        .uploads(ChannelId('UC${'b' * 22}'), shorts: false, sort: VideoSorting.newest);

    expect([for (final v in page.videos) v.title], ['Best of Imran & Porshi', 'Duet']);
    expect([for (final v in page.videos) v.duration], [
      const Duration(hours: 1, minutes: 2, seconds: 3),
      const Duration(minutes: 4, seconds: 5),
    ]);
    expect(page.videos.first.author, 'Sarkar Films');
    expect(page.videos.first.uploadDateRaw, '17h ago');
    expect([for (final v in page.videos) v.engagement.viewCount], [18000, 20000]);

    final next = await page.next!();
    expect([for (final v in next!.videos) v.title], ['Best of Porshi']);
    expect(next.videos.single.engagement.viewCount, 1200000);
    expect(next.next, isNull, reason: 'no more pages');
    expect(http.asked.last, 'browse page2');
  });
}

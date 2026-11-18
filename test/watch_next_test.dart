import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube/watch_next.dart';

// Real YouTube answers (Nov 2026), trimmed to what is read: the watch page of H4-96GqPup4, its first comments
// page and the replies of its first comment.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/watch_next/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('watch page', () {
    test('Up next: the videos with title, channel, length and views; the Shorts shelf is skipped', () {
      final page = WatchNext.parseNext(_fixture('next'));
      expect(page.related.map((v) => v.id.value), ['kGVWLQzr8QM', '20evunLzSgk']);
      final first = page.related.first;
      expect(first.title, 'VUELA-GOYA NOMINATED SHORTFILM');
      expect(first.author, 'Thinkwild Studios');
      expect(first.duration, const Duration(minutes: 15, seconds: 32));
      expect(first.engagement.viewCount, greaterThan(0));
    });

    test('one item that cannot be read does not empty Up next (it used to: a "Streamed …" date threw)', () {
      final json = _fixture('next');
      final results =
          json['contents']['twoColumnWatchNextResults']['secondaryResults']['secondaryResults']['results'] as List;
      results.insert(0, {
        'lockupViewModel': {'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO', 'contentId': 42},
      });
      expect(WatchNext.parseNext(json).related, hasLength(2));
    });

    test('the comments section gives the token for the first comments page', () {
      expect(WatchNext.parseNext(_fixture('next')).commentsToken, startsWith('Eg0SC0g0LTk2R3FQdXA0'));
    });

    test('no comments section (comments turned off): no token', () {
      final json = _fixture('next');
      final contents = json['contents']['twoColumnWatchNextResults']['results']['results']['contents'] as List;
      contents.removeWhere((c) => c is Map && c['itemSectionRenderer'] != null);
      expect(WatchNext.parseNext(json).commentsToken, isNull);
    });
  });

  group('comments', () {
    test('the header gives the total', () {
      final header = _fixture('comments');
      final threads = header['onResponseReceivedEndpoints'] as List;
      expect(WatchNext.parseComments({'onResponseReceivedEndpoints': threads.take(1).toList()}).total, 4390);
    });

    test('each thread: author, text, time, likes, replies, and a token for its replies', () {
      final page = WatchNext.parseComments(_fixture('comments'));
      expect(page.comments, hasLength(2));
      final c = page.comments.first;
      expect(c.author, '@thestrangestfoox2158');
      expect(c.text, startsWith('Just realised the name is ironic'));
      expect(c.publishedTime, '6 years ago');
      expect(c.likeCount, 596);
      expect(c.replyCount, 11);
      expect(c.channelId.value, 'UC2NAO9cTPqHDFTVtJ8bn8CQ');
      expect(page.comments[1].likeCount, 2700, reason: '"2.7K"');
      expect(page.repliesToken(c), isNotNull);
      expect(page.nextToken, isNotNull, reason: 'more comments follow');
    });

    test('a replies page reads the same way', () {
      final page = WatchNext.parseComments(_fixture('replies'));
      expect(page.comments.map((c) => c.text), [
        startsWith('Yasss the late people club'),
        startsWith("I'm happy that there are actually people"),
      ]);
    });

    test('a thread whose comment is missing from the answer is skipped, not shown blank', () {
      final json = _fixture('comments');
      (json['frameworkUpdates']['entityBatchUpdate']['mutations'] as List).removeAt(0);
      expect(WatchNext.parseComments(json).comments, hasLength(1));
    });
  });
}

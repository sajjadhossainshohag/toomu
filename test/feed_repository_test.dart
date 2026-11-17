import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/values/app_constants.dart';
import 'package:toomu/app/data/repositories/feed_repository.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

Video _video(String id, {Duration? duration = const Duration(minutes: 4)}) => Video(
      VideoId(id),
      'Title $id',
      'Author',
      ChannelId('UC${'b' * 22}'),
      null,
      '2 days ago',
      null,
      '',
      duration,
      ThumbnailSet(id),
      null,
      const Engagement(1234, null, null),
      false,
    );

void main() {
  late Directory dir;
  late StorageService storage;
  final now = DateTime(2026, 11, 17, 12);

  setUpAll(() async {
    dir = await useTempStorageDir();
    storage = StorageService(await tempBox('feed_repository_test', dir));
  });
  tearDownAll(() => deleteTempStorageDir(dir));

  test('a saved feed comes back with what the cards show', () async {
    final repo = FeedRepository(storage);
    await repo.save('search:lofi', [_video('dQw4w9WgXcQ'), _video('aqz-KE-bpKQ', duration: null)], now: now);

    final loaded = repo.load('search:lofi', now: now.add(const Duration(hours: 1)))!;

    expect(loaded.map((v) => v.id.value), ['dQw4w9WgXcQ', 'aqz-KE-bpKQ']);
    final v = loaded.first;
    expect(v.title, 'Title dQw4w9WgXcQ');
    expect(v.author, 'Author');
    expect(v.duration, const Duration(minutes: 4));
    expect(v.uploadDateRaw, '2 days ago');
    expect(v.engagement.viewCount, 1234);
    expect(v.thumbnails.highResUrl, contains('dQw4w9WgXcQ'));
    expect(loaded.last.duration, isNull);
  });

  test('an old feed or another category is not shown', () async {
    final repo = FeedRepository(storage);
    await repo.save('search:lofi', [_video('dQw4w9WgXcQ')], now: now);

    expect(repo.load('search:lofi', now: now.add(FeedRepository.maxAge + const Duration(minutes: 1))), isNull);
    expect(repo.load('account:Home', now: now), isNull);
  });

  test('one broken entry does not hide the rest', () async {
    await storage.write(AppConstants.kFeedCache, {
      'category': 'search:lofi',
      'at': now.millisecondsSinceEpoch,
      'videos': [
        {'id': 'dQw4w9WgXcQ', 'title': 'Good', 'author': 'A', 'channelId': 'UC${'b' * 22}'},
        {'id': 'not an id', 'title': 'Bad', 'author': 'A', 'channelId': 'nope'},
      ],
    });

    final loaded = FeedRepository(storage).load('search:lofi', now: now)!;

    expect(loaded.map((v) => v.title), ['Good']);
  });
}

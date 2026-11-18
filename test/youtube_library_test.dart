import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/core/values/app_constants.dart';
import 'package:toomu/app/data/models/saved_videos.dart';
import 'package:toomu/app/data/providers/youtube/account_feed.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

Video _video(String id) => Video(VideoId(id), 'Video $id', 'Author', ChannelId('UC${'b' * 22}'), null, '2 days ago',
    null, '', const Duration(minutes: 4), ThumbnailSet(id), null, const Engagement(1000, null, null), false);

class _Account extends AccountFeed {
  _Account() : super(() async => const {});

  final calls = <String>[];
  Object? failEdit;

  @override
  Future<AccountFeedPage> history() async => AccountFeedPage(this, [_video('seenOnYT001')], null);

  @override
  Future<AccountFeedPage> watchLater() async => AccountFeedPage(this, [_video('laterOnYT01')], null);

  @override
  Future<void> editWatchLater(String videoId, {required bool add}) async {
    calls.add('${add ? 'add' : 'remove'} $videoId');
    if (failEdit != null) throw failEdit!;
  }

  @override
  Future<void> markWatched(String videoId) async => calls.add('watched $videoId');
}

void main() {
  late Directory dir;
  var box = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  late StorageService storage;
  setUp(() async {
    storage = Get.put(StorageService(await tempBox('library_${box++}', dir)));
    await storage.write(AppConstants.kWatchLater, SavedVideos.write([_video('laterOnPhon')]));
    Get.put(YoutubeAccountService());
    Get.put(RemoteConfigService());
  });
  tearDown(Get.reset);

  Future<YoutubeController> open(_Account account, {required bool signedIn}) async {
    YoutubeAccountService.to.signedIn.value = signedIn;
    final yt = Get.put(YoutubeController(account: account));
    await yt.loadLibrary();
    return yt;
  }

  test('signed in: History and Watch later are the YouTube account\'s own', () async {
    final yt = await open(_Account(), signedIn: true);
    expect(yt.watched.map((v) => v.id.value), ['seenOnYT001']);
    expect(yt.watchLater.map((v) => v.id.value), ['laterOnYT01']);
  });

  test('signed out: the lists kept on the phone', () async {
    final yt = await open(_Account(), signedIn: false);
    expect(yt.watchLater.map((v) => v.id.value), ['laterOnPhon']);
  });

  // Widget tests: saving shows a snack, which needs an app on screen.
  testWidgets('signed in, saving and removing change the YouTube playlist, not the phone\'s list', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    final account = _Account();
    final yt = await open(account, signedIn: true);
    yt.toggleWatchLater(_video('newVideo001'));
    yt.toggleWatchLater(_video('laterOnYT01'));
    await tester.pump();
    expect(account.calls, ['add newVideo001', 'remove laterOnYT01']);
    expect(yt.watchLater.map((v) => v.id.value), ['newVideo001']);
    expect(SavedVideos.read(storage.read<List>(AppConstants.kWatchLater)).map((v) => v.id.value), ['laterOnPhon']);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('signed in, a save YouTube refused is undone on screen', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    final account = _Account()..failEdit = const SocketException('offline');
    final yt = await open(account, signedIn: true);
    yt.toggleWatchLater(_video('newVideo001'));
    expect(yt.isSaved(_video('newVideo001')), isTrue, reason: 'shown at once');
    await tester.pump();
    expect(yt.isSaved(_video('newVideo001')), isFalse);
    await tester.pump(const Duration(seconds: 10));
  });
}

part of 'app_pages.dart';

abstract class Routes {
  Routes._();

  static const home = _Paths.home;
  static const player = _Paths.player;
  static const musicCollection = _Paths.musicCollection;
  static const browser = _Paths.browser;
  static const videoPlayer = _Paths.videoPlayer;
  static const videoFolder = _Paths.videoFolder;
  static const channel = _Paths.channel;
  static const shorts = _Paths.shorts;
}

abstract class _Paths {
  _Paths._();

  static const home = '/home';
  static const player = '/player';
  static const musicCollection = '/music/collection';
  static const browser = '/browser';
  static const videoPlayer = '/video';
  static const videoFolder = '/videos/folder';
  static const channel = '/youtube/channel';
  static const shorts = '/youtube/shorts';
}

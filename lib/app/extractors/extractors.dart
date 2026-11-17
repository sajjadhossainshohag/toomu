import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../core/theme/color_constants.dart';
import 'direct_file_extractor.dart';
import 'media_extractor.dart';
import 'youtube_extractor.dart';

export 'media_extractor.dart';

/// Registry of supported sites. Order = priority.
abstract class Extractors {
  static const List<MediaExtractor> all = <MediaExtractor>[
    YoutubeExtractor(),
    DirectFileExtractor(),
  ];

  static MediaExtractor? find(Uri uri) {
    for (final e in all) {
      if (e.canHandle(uri)) return e;
    }
    return null;
  }

  /// Start-page sites; replaced by remote config when it provides `sites`.
  static const List<SiteShortcut> defaultSites = <SiteShortcut>[
    SiteShortcut(
      name: 'YouTube',
      url: 'https://m.youtube.com/',
      icon: Iconsax.video_play_copy,
      color: ColorConstants.siteYoutube,
    ),
    SiteShortcut(
      name: 'YT Music',
      url: 'https://music.youtube.com/',
      icon: Iconsax.music_copy,
      color: ColorConstants.siteYoutubeMusic,
    ),
    SiteShortcut(
      name: 'Google',
      url: 'https://www.google.com/',
      icon: Iconsax.global_search_copy,
      color: ColorConstants.siteGoogle,
    ),
  ];
}

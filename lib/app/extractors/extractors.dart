import 'package:flutter/material.dart';

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
      icon: Icons.smart_display_rounded,
      color: ColorConstants.siteYoutube,
    ),
    SiteShortcut(
      name: 'YT Music',
      url: 'https://music.youtube.com/',
      icon: Icons.library_music_rounded,
      color: ColorConstants.siteYoutubeMusic,
    ),
    SiteShortcut(
      name: 'Google',
      url: 'https://www.google.com/',
      icon: Icons.travel_explore_rounded,
      color: ColorConstants.siteGoogle,
    ),
  ];
}

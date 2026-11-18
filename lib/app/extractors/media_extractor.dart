import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// One supported site (Snaptube-style plug-in). The browser asks every
/// extractor whether it can handle the current page; the first match gets
/// the floating Download button.
///
/// To add a site (Instagram, TikTok, Facebook…): implement this class, then
/// register it in [Extractors.all].
abstract class MediaExtractor {
  const MediaExtractor();

  String get id;
  String get name;

  /// True when [uri] points at something this extractor can download.
  bool canHandle(Uri uri);

  /// Starts the download flow for [uri] (format picker, confirm sheet…).
  Future<void> openDownload(Uri uri);
}

/// A site shown on the home page / browser start page.
class SiteShortcut {
  const SiteShortcut({
    required this.name,
    required this.url,
    required this.icon,
    required this.color,
  });

  final String name;
  final String url;
  final IconData icon;
  final Color color;

  factory SiteShortcut.fromJson(Map<String, dynamic> json) => SiteShortcut(
        name: json['name'] as String,
        url: json['url'] as String,
        icon: _icons[json['icon']] ?? Iconsax.global_copy,
        color: Color(int.tryParse('${json['color'] ?? ''}'.replaceFirst('#', 'FF'), radix: 16) ??
            0xFF3D63DD),
      );

  static const _icons = <String, IconData>{
    'video': Iconsax.video_play_copy,
    'music': Iconsax.music_copy,
    'search': Iconsax.global_search_copy,
    'globe': Iconsax.global_copy,
    'facebook': Icons.facebook,
  };
}

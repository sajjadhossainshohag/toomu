import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/design_metrics.dart';
import '../address.dart';

/// A site's own icon (its /favicon.ico, from the site itself rather than
/// a third-party icon service), else its first letter on a colour of its
/// own.
class SiteIcon extends StatelessWidget {
  const SiteIcon({required this.url, this.size = 20, super.key});

  final String url;
  final double size;

  static const _colors = <Color>[
    Color(0xFF7C4DFF),
    Color(0xFF3D63DD),
    Color(0xFF12A150),
    Color(0xFFDC6803),
    Color(0xFFE63946),
    Color(0xFF0E9AA7),
    Color(0xFF9C27B0),
  ];

  @override
  Widget build(BuildContext context) {
    final double s = size * context.scale;
    final uri = Uri.tryParse(url);
    final host = displayAddress(url);
    final letter = Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colors[host.codeUnits.fold<int>(0, (a, c) => a + c) % _colors.length],
        borderRadius: BorderRadius.circular(s / 4),
      ),
      child: Text(
        host.isEmpty ? '·' : host[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: s * 0.55, fontWeight: FontWeight.w700, height: 1),
      ),
    );
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return letter;
    return ClipRRect(
      borderRadius: BorderRadius.circular(s / 4),
      child: CachedNetworkImage(
        imageUrl: '${uri.scheme}://${uri.host}/favicon.ico',
        width: s,
        height: s,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        placeholder: (_, _) => letter,
        errorWidget: (_, _, _) => letter,
      ),
    );
  }
}

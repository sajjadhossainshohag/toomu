import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../image_menu.dart';
import '../link_menu.dart';

/// One row of the menu: its label and what it does ([LinkAction] or
/// [ImageAction]).
typedef PageMenuEntry = ({String label, Object action});

/// The rows for a long press: the link's, then the picture's (an image
/// inside a link gets both, like Chrome).
List<PageMenuEntry> pageMenuEntries({PageLink? link, PageImage? image, required bool canCopyImage}) => [
  if (link != null)
    for (final a in linkActions(link)) (label: a.label, action: a),
  if (image != null)
    for (final a in imageActions(image, canCopyImage: canCopyImage)) (label: a.label, action: a),
];

/// Chrome-style menu for a long-pressed link or image: a header with the
/// picture and the link's words or image's alt text, then one row per
/// action. Returns the chosen action.
Future<Object?> showPageMenu({PageLink? link, PageImage? image, required List<PageMenuEntry> entries}) =>
    Get.dialog<Object>(
      PageMenuDialog(
        link: link,
        image: image,
        entries: entries,
        onPick: (a) => Get.back(result: a),
      ),
      barrierColor: ColorConstants.black.withValues(alpha: 0.4),
    );

class PageMenuDialog extends StatelessWidget {
  const PageMenuDialog({this.link, this.image, required this.entries, required this.onPick, super.key})
    : assert(link != null || image != null);

  final PageLink? link;
  final PageImage? image;
  final List<PageMenuEntry> entries;
  final ValueChanged<Object> onPick;

  String get _title => link != null && link!.text.trim().isNotEmpty ? link!.title : (image?.title ?? link!.title);

  /// The link's address under its words (Chrome shows where it goes).
  String? get _subtitle => link != null && _title != link!.href ? link!.href : null;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 24 * scale),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 340 * scale),
          child: Material(
            color: ColorConstants.surfaceOn(dark),
            borderRadius: BorderRadius.circular(28 * scale),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(20 * scale, 20 * scale, 20 * scale, 16 * scale),
                    child: Row(
                      children: <Widget>[
                        if (image != null) ...<Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8 * scale),
                            child: SizedBox(
                              width: 56 * scale,
                              height: 56 * scale,
                              child: ImageThumb(image: image!, iconColor: ink.withValues(alpha: 0.4)),
                            ),
                          ),
                          SizedBox(width: 16 * scale),
                        ] else ...<Widget>[
                          Icon(Icons.link_rounded, size: 22 * scale, color: ink.withValues(alpha: 0.5)),
                          SizedBox(width: 14 * scale),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: ink.withValues(alpha: 0.8),
                                ),
                              ),
                              if (_subtitle != null)
                                Text(
                                  _subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.5)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: ink.withValues(alpha: 0.08)),
                  SizedBox(height: 6 * scale),
                  for (final e in entries)
                    InkWell(
                      onTap: () => onPick(e.action),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 14 * scale),
                        child: Text(
                          e.label,
                          style: TextStyle(
                            fontSize: 15 * scale,
                            height: 20 / 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  SizedBox(height: 6 * scale),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture itself, fetched like the page fetched it (same Referer,
/// cookies). Inline images come from their bytes; blob images only exist
/// inside the page, so they get an icon.
class ImageThumb extends StatelessWidget {
  const ImageThumb({required this.image, this.iconColor, this.fit = BoxFit.cover, super.key});

  final PageImage image;
  final Color? iconColor;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget placeholder(BuildContext _, Object _, StackTrace? _) =>
        Center(child: Icon(Icons.image_outlined, color: iconColor));
    if (image.isWebLink) {
      return Image.network(image.src, headers: image.headers, fit: fit, errorBuilder: placeholder);
    }
    final Uint8List? bytes = decodeDataImage(image.src)?.bytes;
    if (bytes != null) return Image.memory(bytes, fit: fit, errorBuilder: placeholder);
    return placeholder(context, '', null);
  }
}

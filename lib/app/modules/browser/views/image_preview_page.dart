import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/design_metrics.dart';
import '../../../widgets/round_icon_button.dart';

/// "Preview image": the picture on black, pinch to zoom, without leaving
/// the page underneath.
class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({required this.title, required this.bytes, super.key});

  final String title;

  /// Loads the picture (already fetched with the page's headers).
  final Future<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      "Couldn't load the image.",
                      style: TextStyle(color: Colors.white70, fontSize: 14 * scale),
                    ),
                  );
                }
                final data = snap.data;
                if (data == null) return const Center(child: CircularProgressIndicator(color: Colors.white70));
                return InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: Image.memory(
                      data,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        "This image can't be shown.",
                        style: TextStyle(color: Colors.white70, fontSize: 14 * scale),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12 * scale),
              child: Row(
                children: <Widget>[
                  RoundIconButton(icon: Icons.close_rounded, size: 40, onTap: Get.back, tooltip: 'Close'),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 15 * scale, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

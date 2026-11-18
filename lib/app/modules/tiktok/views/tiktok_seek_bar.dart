import 'package:flutter/material.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';

/// TikTok's seek bar: a thin line of the time played; drag along it (or
/// tap) to go forward or back. While dragging it thickens and the time
/// shows big above it ("0:12 / 0:30"); the video jumps there on release.
class TiktokSeekBar extends StatefulWidget {
  const TiktokSeekBar({
    super.key,
    required this.position,
    required this.total,
    required this.onSeek,
    this.initial = Duration.zero,
  });

  final Stream<Duration> position;
  final Duration Function() total;
  final Future<void> Function(Duration to) onSeek;
  final Duration initial;

  /// Where a touch at [dx] of a bar [width] wide goes in a video of [total].
  static Duration target(double dx, double width, Duration total) {
    if (width <= 0 || total <= Duration.zero) return Duration.zero;
    return total * (dx / width).clamp(0.0, 1.0);
  }

  @override
  State<TiktokSeekBar> createState() => _TiktokSeekBarState();
}

class _TiktokSeekBarState extends State<TiktokSeekBar> {
  /// Where the finger is (while dragging).
  Duration? _drag;

  void _move(double dx, double width) =>
      setState(() => _drag = TiktokSeekBar.target(dx, width, widget.total()));

  Future<void> _release() async {
    final to = _drag;
    if (to == null) return;
    await widget.onSeek(to);
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return LayoutBuilder(
      builder: (_, box) {
        final width = box.maxWidth;
        return StreamBuilder<Duration>(
          stream: widget.position,
          initialData: widget.initial,
          builder: (_, snap) {
            final total = widget.total();
            final at = _drag ?? snap.data ?? Duration.zero;
            final done = total <= Duration.zero
                ? 0.0
                : (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            final dragging = _drag != null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (dragging)
                  Padding(
                    padding: EdgeInsets.only(bottom: 18 * scale),
                    child: Text.rich(
                      TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text: Formatters.duration(at),
                            style: const TextStyle(color: ColorConstants.white),
                          ),
                          TextSpan(
                            text: ' / ${Formatters.duration(total)}',
                            style: TextStyle(
                              color: ColorConstants.white.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 26 * scale,
                        fontWeight: FontWeight.w700,
                        shadows: const <Shadow>[
                          Shadow(blurRadius: 8, color: Color(0x99000000)),
                        ],
                      ),
                    ),
                  ),
                // A tall touch area around the thin line.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) =>
                      _move(d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) =>
                      _move(d.localPosition.dx, width),
                  onHorizontalDragEnd: (_) => _release(),
                  onHorizontalDragCancel: () => setState(() => _drag = null),
                  onTapUp: (d) {
                    _move(d.localPosition.dx, width);
                    _release();
                  },
                  child: SizedBox(
                    height: 22 * scale,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _Line(done: done, thick: dragging),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.done, required this.thick});

  final double done;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    final double h = thick ? 6 : 2;
    return SizedBox(
      height: thick ? 14 : 2,
      child: LayoutBuilder(
        builder: (_, box) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: <Widget>[
            Container(
              height: h,
              color: ColorConstants.white.withValues(alpha: 0.25),
            ),
            Container(
              height: h,
              width: box.maxWidth * done,
              color: ColorConstants.white.withValues(alpha: 0.9),
            ),
            if (thick)
              Positioned(
                left: box.maxWidth * done - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: ColorConstants.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

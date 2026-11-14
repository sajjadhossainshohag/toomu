import 'package:flutter/material.dart';

class GradientRoundedBorder extends StatelessWidget {
  const GradientRoundedBorder({
    required this.radius,
    required this.gradient,
    required this.child,
    this.strokeWidth = 1,
    super.key,
  });

  final double radius;
  final Gradient gradient;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _Painter(radius, gradient, strokeWidth),
        child: child,
      );
}

class _Painter extends CustomPainter {
  const _Painter(this.radius, this.gradient, this.strokeWidth);

  final double radius;
  final Gradient gradient;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(strokeWidth / 2), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = gradient.createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.radius != radius || old.gradient != gradient || old.strokeWidth != strokeWidth;
}

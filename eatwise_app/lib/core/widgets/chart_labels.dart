import 'package:flutter/material.dart';

/// Place chart labels using their measured width. Reserve the newest value
/// first, then the oldest, so clamping edge labels never makes them collide.
class ChartLabelLayout {
  ChartLabelLayout({
    required this.width,
    required this.style,
    this.textScaler = TextScaler.noScaling,
  });

  final double width;
  final TextStyle style;
  final TextScaler textScaler;
  final List<Rect> bounds = [];

  TextPainter? place(String text, double centerX, double top) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    if (painter.width > width) return null;
    final left = (centerX - painter.width / 2).clamp(
      0.0,
      width - painter.width,
    );
    final rect = Rect.fromLTWH(left, top, painter.width, painter.height);
    if (bounds.any((other) => other.inflate(6).overlaps(rect))) return null;
    bounds.add(rect);
    return painter;
  }

  void paint(Canvas canvas, String text, double centerX, double top) {
    final painter = place(text, centerX, top);
    if (painter != null) painter.paint(canvas, bounds.last.topLeft);
  }
}

Iterable<int> chartLabelPriority(int length) sync* {
  if (length == 0) return;
  yield length - 1;
  if (length > 1) yield 0;
  for (var i = 1; i < length - 1; i++) {
    yield i;
  }
}

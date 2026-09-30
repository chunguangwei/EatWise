import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 卡内迷你图表族（2026-09-30 UI 换代共享组件，华为运动健康卡片语言）：
/// 心率折线 / 血氧柱状 / 睡眠分段条三种形态，统一「无坐标轴、无网格、
/// 无标签」——卡片里的图只负责给出形状趋势，具体数值由卡片大数字承担。
///
/// 三者都接受空数据（渲染为空白占位，不抛异常、不画误导性的零线）。

/// 迷你折线（带渐隐面积填充；华为「心脏健康」卡语言）。
///
/// [values] 为等间距采样序列；null 项表示断点（不连线），与趋势图
/// 「无数据不补零」口径一致。
class MiniSparkline extends StatelessWidget {
  const MiniSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 40,
    this.strokeWidth = 2,
  });

  final List<double?> values;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double?> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList(growable: false);
    if (present.length < 2) return;
    var min = present.reduce(math.min);
    var max = present.reduce(math.max);
    if (max - min < 1e-9) {
      // 全等值：画水平中线，避免除零把线拍到顶/底。
      min -= 1;
      max += 1;
    }
    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    double yOf(double v) => size.height * (1 - (v - min) / (max - min));

    // 断点分段：null 处断开，分别成段。
    final segments = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (current.length > 1) segments.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(Offset(stepX * i, yOf(v)));
    }
    if (current.length > 1) segments.add(current);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final seg in segments) {
      final path = Path()..moveTo(seg.first.dx, seg.first.dy);
      for (final p in seg.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      // 渐隐面积填充（线下方），华为卡片图表的柔和观感来源。
      final fill = Path.from(path)
        ..lineTo(seg.last.dx, size.height)
        ..lineTo(seg.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// 迷你柱状（华为「血氧饱和度」卡语言）。
///
/// [values] 为 0..1 归一化高度；null 项渲染为空档（不画柱）。
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.color,
    this.height = 40,
    this.barWidth = 3,
  });

  final List<double?> values;
  final Color color;
  final double height;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarsPainter(values: values, color: color, barWidth: barWidth),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.color,
    required this.barWidth,
  });

  final List<double?> values;
  final Color color;
  final double barWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final w = math.min(barWidth, slot * 0.7);
    final paint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || v <= 0) continue;
      final h = size.height * v.clamp(0.0, 1.0);
      final left = slot * i + (slot - w) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, w, h),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.color != color || old.barWidth != barWidth;
}

/// 分段条的一段（值 + 色）。
@immutable
final class SegmentSpec {
  const SegmentSpec({required this.weight, required this.color});

  /// 相对权重（按总和归一化）。
  final double weight;
  final Color color;
}

/// 迷你分段条（华为「睡眠」卡语言：深睡/浅睡/清醒分段）。
class MiniSegmentBar extends StatelessWidget {
  const MiniSegmentBar({
    super.key,
    required this.segments,
    this.height = 26,
    this.gap = 2,
  });

  final List<SegmentSpec> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + math.max(0, e.weight));
    if (total <= 0) return SizedBox(height: height, width: double.infinity);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < segments.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              flex: math.max(1, (segments[i].weight / total * 1000).round()),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: segments[i].color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

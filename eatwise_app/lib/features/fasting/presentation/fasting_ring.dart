import 'dart:math' as math;

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 断食计时环（设计稿 §4.1：SVG/conic 圆环，直径 220px，`radius-full`；
/// 断食进行态轻盈绿弧、进食窗暖阳橙弧，中心 48px Inter Bold 数字 + 状态文案）。
///
/// Flutter 端以 CustomPaint 实现 conic 弧（与小组件同锚点，误差 ≈0，
/// 《规格-M2》§8：双端均渲染「锚点 − now」）。
class FastingRing extends StatelessWidget {
  const FastingRing({
    required this.progress,
    required this.arcColor,
    required this.child,
    super.key,
    this.size = 220,
  });

  /// 进度 0..1（断食：已断食时长 ÷ 计划时长；进食：已进食时长 ÷ 窗口时长）。
  final double progress;

  /// 弧色（断食 `brandPrimary` / 进食 `brandAccent`，语义固定）。
  final Color arcColor;

  /// 环中心内容（倒计时数字 + 状态文案）。
  final Widget child;

  /// 环直径（设计稿 220px）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          arcColor: arcColor,
          trackColor: colors.border.withValues(alpha: 0.2),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.arcColor,
    required this.trackColor,
  });

  final double progress;
  final Color arcColor;
  final Color trackColor;

  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底环（雾灰派生，透明度由组件定，Token 规范 §2.2 border 约束）。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = trackColor,
    );

    // conic 进度弧：12 点方向起笔，圆头收尾。
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * clamped,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = arcColor,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.arcColor != arcColor ||
        oldDelegate.trackColor != trackColor;
  }
}

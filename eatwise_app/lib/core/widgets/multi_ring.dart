import 'dart:math' as math;

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 多环进度的一条环（2026-09-29 UI 重构共享组件）。
@immutable
final class RingSpec {
  const RingSpec({
    required this.progress,
    required this.color,
    this.gradient,
    this.label,
  });

  /// 0..1（>1 截断；苹果「超额转满」口径由调用方决定，本组件只裁剪）。
  final double progress;

  /// 环色（无渐变时使用）。
  final Color color;

  /// 可选渐变（沿弧方向 sweep）。
  final Gradient? gradient;

  /// 语义标签（无障碍；如「断食进度」）。
  final String? label;
}

/// 多环进度组件：同心圆环 + 圆头端点 + 轨道暗纹 + 可选渐变 + 中心内容槽。
///
/// 视觉融合苹果健身「活动三环」（圆头、轨道、同心嵌套）与华为运动健康
/// 「健康三叶草」（多指标同盘）。最外环为 [rings] 第一项，向内依次嵌套。
/// 纯展示，零业务逻辑；配色一律走 Token（[AppColors] ring* 组）。
class MultiRingProgress extends StatelessWidget {
  const MultiRingProgress({
    super.key,
    required this.rings,
    this.size = 220,
    this.strokeWidth = 16,
    this.gap = 6,
    this.center,
    this.trackOpacity,
  });

  /// 外→内嵌套的环（1–4 条观感最佳）。
  final List<RingSpec> rings;

  /// 组件边长（正方形）。
  final double size;

  /// 最外环宽度；内环按 0.85 递减（华为三叶草内环略细）。
  final double strokeWidth;

  /// 环间距。
  final double gap;

  /// 中心内容槽（倒计时/大数字等）。
  final Widget? center;

  /// 轨道透明度（null 自动：亮 0.12 / 暗 0.22）。
  final double? trackOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final brightness = Theme.of(context).brightness;
    final track =
        (trackOpacity ?? (brightness == Brightness.dark ? 0.22 : 0.12));
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MultiRingPainter(
          rings: rings,
          strokeWidth: strokeWidth,
          gap: gap,
          trackColor: colors.textSecondary.withValues(alpha: track),
        ),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

class _MultiRingPainter extends CustomPainter {
  _MultiRingPainter({
    required this.rings,
    required this.strokeWidth,
    required this.gap,
    required this.trackColor,
  });

  final List<RingSpec> rings;
  final double strokeWidth;
  final double gap;
  final Color trackColor;

  static const double _startAngle = -math.pi / 2; // 12 点起顺时针

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    for (var i = 0; i < rings.length; i++) {
      final spec = rings[i];
      final width = strokeWidth * math.pow(0.85, i).toDouble();
      final inset = i * (strokeWidth + gap) + width / 2;
      final ringRect = rect.deflate(inset);
      // 轨道（整圈暗纹）。
      canvas.drawArc(
        ringRect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = trackColor,
      );
      final progress = spec.progress.clamp(0.0, 1.0);
      if (progress <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      final gradient = spec.gradient;
      if (gradient != null) {
        paint.shader = gradient.createShader(ringRect);
      } else {
        paint.color = spec.color;
      }
      canvas.drawArc(
        ringRect,
        _startAngle,
        math.pi * 2 * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MultiRingPainter oldDelegate) {
    return oldDelegate.rings != rings ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap ||
        oldDelegate.trackColor != trackColor;
  }
}

import 'dart:math' as math;

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 开口环仪表的一条弧（2026-09-30 UI 换代共享组件）。
@immutable
final class ArcSpec {
  const ArcSpec({
    required this.progress,
    required this.color,
    this.icon,
    this.label,
  });

  /// 0..1（>1 截断；「超额转满」口径由调用方决定，本组件只裁剪）。
  final double progress;

  /// 弧色；轨道自动取同色低透明度（华为口径：轨道是弧色的淡版，不是中性灰）。
  final Color color;

  /// 端点图标（白色小图标，画在进度端圆头里；null 则不画）。
  final IconData? icon;

  /// 语义标签（无障碍，如「活动热量」）。
  final String? label;
}

/// 开口环仪表（华为运动健康「今日」页三环仪表语言）：
/// 底部开口的多条同心弧 + 同色系浅轨道 + 圆头端点 + 端点内嵌白色图标 +
/// 中心内容槽。
///
/// 与已下线的 MultiRingProgress（闭合整圈，苹果活动环语言）的历史分工：
/// 本组件用于「多指标并置的仪表盘」场景（首页今日总览），开口处天然留出
/// 视觉呼吸与图例位；闭合环用于「单一周期进度」场景（断食倒计时）。
///
/// 纯展示，零业务逻辑；配色一律走 Token（[AppColors] gauge* 组）。
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    super.key,
    required this.arcs,
    this.size = 200,
    this.strokeWidth = 14,
    this.gap = 5,
    this.center,
    this.startDegrees = 135,
    this.sweepDegrees = 270,
    this.trackOpacity,
  });

  /// 外→内嵌套的弧（1–3 条观感最佳）。
  final List<ArcSpec> arcs;

  /// 组件边长（正方形）。
  final double size;

  /// 弧宽（各环等宽——华为仪表不做内环递减，与苹果活动环不同）。
  final double strokeWidth;

  /// 环间距。
  final double gap;

  /// 中心内容槽。
  final Widget? center;

  /// 起始角（度，0=3 点方向，顺时针为正；默认 135=左下开口起点）。
  final double startDegrees;

  /// 扫掠角（度；默认 270，底部留 90° 开口）。
  final double sweepDegrees;

  /// 轨道透明度（null 自动：亮 0.16 / 暗 0.26）。
  final double? trackOpacity;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final track = trackOpacity ?? (brightness == Brightness.dark ? 0.26 : 0.16);
    final startRad = startDegrees * math.pi / 180;
    final sweepRad = sweepDegrees * math.pi / 180;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _ArcGaugePainter(
              arcs: arcs,
              strokeWidth: strokeWidth,
              gap: gap,
              trackOpacity: track,
              startRad: startRad,
              sweepRad: sweepRad,
            ),
          ),
          // 端点图标：以 Stack 叠加而非入画布，图标渲染更清晰且可走主题字体。
          for (var i = 0; i < arcs.length; i++)
            if (arcs[i].icon != null && arcs[i].progress > 0)
              _EndCapIcon(
                icon: arcs[i].icon!,
                size: size,
                radius: _radiusOf(i),
                angle: startRad + sweepRad * arcs[i].progress.clamp(0.0, 1.0),
                diameter: strokeWidth,
              ),
          ?center,
        ],
      ),
    );
  }

  /// 第 i 条弧的中心线半径（外→内）。
  double _radiusOf(int i) {
    return size / 2 - (i * (strokeWidth + gap) + strokeWidth / 2);
  }
}

/// 进度端圆头内的白色小图标。
class _EndCapIcon extends StatelessWidget {
  const _EndCapIcon({
    required this.icon,
    required this.size,
    required this.radius,
    required this.angle,
    required this.diameter,
  });

  final IconData icon;
  final double size;
  final double radius;
  final double angle;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Icon(icon, size: diameter * 0.62, color: Colors.white),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  _ArcGaugePainter({
    required this.arcs,
    required this.strokeWidth,
    required this.gap,
    required this.trackOpacity,
    required this.startRad,
    required this.sweepRad,
  });

  final List<ArcSpec> arcs;
  final double strokeWidth;
  final double gap;
  final double trackOpacity;
  final double startRad;
  final double sweepRad;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (var i = 0; i < arcs.length; i++) {
      final spec = arcs[i];
      final inset = i * (strokeWidth + gap) + strokeWidth / 2;
      final arcRect = rect.deflate(inset);
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // 轨道：弧色淡版（华为口径），整条开口弧。
      canvas.drawArc(
        arcRect,
        startRad,
        sweepRad,
        false,
        base..color = spec.color.withValues(alpha: trackOpacity),
      );

      final progress = spec.progress.clamp(0.0, 1.0);
      if (progress <= 0) continue;
      canvas.drawArc(
        arcRect,
        startRad,
        sweepRad * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = spec.color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) {
    return old.arcs != arcs ||
        old.strokeWidth != strokeWidth ||
        old.gap != gap ||
        old.trackOpacity != trackOpacity ||
        old.startRad != startRad ||
        old.sweepRad != sweepRad;
  }
}

/// 仪表图例的一列（圆点 + 标签 + 大数字 + /目标）。
@immutable
final class GaugeLegendItem {
  const GaugeLegendItem({
    required this.color,
    required this.label,
    required this.value,
    this.goal,
  });

  /// 圆点色（与对应弧同色）。
  final Color color;

  /// 指标名（如「活动热量」）。
  final String label;

  /// 当前值大数字（如「209」）。
  final String value;

  /// 目标说明（如「/701 千卡」；null 则不渲染该行）。
  final String? goal;
}

/// 仪表图例行（华为「活动热量 / 锻炼时长 / 活动小时数」三列）。
///
/// 中英文适配：标签与目标行均 [FittedBox] 缩放兜底——英文文案（如
/// "Active energy" / "Exercise minutes"）显著长于中文，窄屏等分三列时
/// 必须允许缩放，否则溢出或被截断。
class GaugeLegendRow extends StatelessWidget {
  const GaugeLegendRow({super.key, required this.items});

  final List<GaugeLegendItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.divider,
                indent: 4,
                endIndent: 4,
              ),
            Expanded(child: _LegendColumn(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _LegendColumn extends StatelessWidget {
  const _LegendColumn({required this.item});

  final GaugeLegendItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Semantics(
      label: item.goal == null
          ? '${item.label} ${item.value}'
          : '${item.label} ${item.value} ${item.goal}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  item.label,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.value,
              style: textStyles.text3xl.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
            ),
          ),
          if (item.goal != null) ...<Widget>[
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.goal!,
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

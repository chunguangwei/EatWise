import 'package:eatwise/core/widgets/arc_gauge.dart';
import 'package:flutter/material.dart';

/// 断食计时环（默认直径 240px；断食进行态品牌绿弧、进食窗琥珀弧，
/// 中心倒计时数字与状态文案按内环空间缩放）。
///
/// 2026-09-30 UI 换代 v2：由闭合整圈（苹果活动环语言）改为**底部开口的
/// 多环仪表**（[ArcGauge]，华为运动健康「今日」页语言）。改动理由：
/// - 开口处天然让出视觉呼吸位，中心倒计时（34px 大数字 + 状态行）不再被
///   整圈环线包死，可读性提升；
/// - 支持在同一盘面上并置多个今日指标（断食/热量/饮水），与下方三列图例
///   构成华为式「一盘三指标」总览，而不是环 + 卡片两套割裂的信息。
///
/// 对外 API 向后兼容：仅新增可选的 [secondary]/[tertiary] 环，
/// 既有调用（progress/arcColor/child/size）行为不变。
///
/// Flutter 端以 CustomPaint 实现弧（与小组件同锚点，误差 ≈0，
/// 《规格-M2》§8：双端均渲染「锚点 − now」）。
class FastingRing extends StatelessWidget {
  const FastingRing({
    required this.progress,
    required this.arcColor,
    required this.child,
    super.key,
    this.size = 240,
    this.secondary,
    this.tertiary,
  });

  /// 进度 0..1（断食：已断食时长 ÷ 计划时长；进食：已进食时长 ÷ 窗口时长）。
  final double progress;

  /// 弧色（断食 `brandPrimary` / 进食 `brandAccent`，语义固定）。
  final Color arcColor;

  /// 环中心内容（倒计时数字 + 状态文案）。
  final Widget child;

  /// 环直径。
  final double size;

  /// 第二环（中环，通常为今日热量；null 则只画主环）。
  final ArcSpec? secondary;

  /// 第三环（内环，通常为今日饮水；null 则不画）。
  final ArcSpec? tertiary;

  @override
  Widget build(BuildContext context) {
    return ArcGauge(
      size: size,
      strokeWidth: 14,
      gap: 6,
      arcs: <ArcSpec>[
        ArcSpec(progress: progress, color: arcColor, icon: Icons.timer_rounded),
        ?secondary,
        ?tertiary,
      ],
      center: child,
    );
  }
}

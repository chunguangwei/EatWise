import 'package:eatwise/core/widgets/multi_ring.dart';
import 'package:flutter/material.dart';

/// 断食计时环（设计稿 §4.1：SVG/conic 圆环，直径 220px，`radius-full`；
/// 断食进行态轻盈绿弧、进食窗暖阳橙弧，中心 48px Inter Bold 数字 + 状态文案）。
///
/// 2026-09-29 UI 重构：内部改由共享 [MultiRingProgress] 渲染——渐变弧
/// （品牌色 55% → 100% 沿弧加深）+ 圆头端点 + 轨道暗纹，对齐苹果活动环/
/// 华为健康环观感；对外 API（progress/arcColor/child/size）不变。
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
    return MultiRingProgress(
      size: size,
      strokeWidth: 14,
      rings: <RingSpec>[
        RingSpec(
          progress: progress,
          color: arcColor,
          gradient: SweepGradient(
            // 12 点起顺时针（断言要求 0≤start<end≤2π，用旋转对齐 12 点）。
            startAngle: 0,
            endAngle: 6.2832,
            transform: const GradientRotation(-1.5708),
            colors: <Color>[arcColor.withValues(alpha: 0.55), arcColor],
          ),
        ),
      ],
      center: child,
    );
  }
}

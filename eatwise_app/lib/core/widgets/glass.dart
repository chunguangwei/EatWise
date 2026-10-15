import 'dart:ui' show ImageFilter;

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:flutter/material.dart';

/// 液态玻璃材质基元（2026-10-15 v1.17.0 质感升级，用户拍板「苹果液态玻璃
/// + 华为简约」方向，预览图确认后实施）。
///
/// 设计语言三要素：
/// - **磨砂半透明**：BackdropFilter 高斯模糊 + 半透明底色（导航/弹层）；
/// - **受光描边**：1px 高光边（亮色主题=顶部受光的白边，暗色=微弱白边），
///   是玻璃「光泽感」的核心来源——只有投影没有受光面的卡片「浮起但不亮」；
/// - **渐变光泽**：环弧/主按钮的明暗流动（见 arc_gauge.dart / ButtonGloss）。
///
/// 性能纪律：BackdropFilter 在低端安卓昂贵，只用在底部导航与弹层两个
/// 常驻/关键视觉位；卡片光泽一律走纯 BoxDecoration（零模糊成本）。
abstract final class AppGlass {
  /// 磨砂面板底色透明度（亮色 0.72 / 暗色 0.62：暗色底色深，再透明会糊）。
  static double tintOpacity(AppColors colors) => _isDark(colors) ? 0.62 : 0.72;

  /// 受光描边色（亮色=白 55%；暗色=白 10%）。
  static Color highlight(AppColors colors) =>
      Colors.white.withValues(alpha: _isDark(colors) ? 0.10 : 0.55);

  /// 磨砂模糊强度（导航/弹层共用）。
  static const double blurSigma = 24;

  static bool _isDark(AppColors colors) =>
      colors.bgPrimary.computeLuminance() < 0.5;
}

/// 卡片装饰（内容卡唯一入口，v1.17.0 起替代各页手写 BoxDecoration）：
/// 白卡 + shadowSm + 1px 受光描边。纯装饰零模糊，任意页面放心用。
///
/// `onMaterial`：卡片外层已是 `Material(color: bgSecondary)` 时传 true——
/// 底色由 Material 绘制，本装饰只带圆角/阴影/受光描边。**必须**这样做：
/// ListTile/InkWell 的水波纹画在最近 Material 祖先上，若中间 DecoratedBox
/// 再带 color 会触发框架「ink splashes may be invisible」断言。
abstract final class AppSurfaces {
  static BoxDecoration card(
    AppColors colors,
    AppShadows shadows, {
    BorderRadius? radius,
    bool onMaterial = false,
  }) {
    return BoxDecoration(
      color: onMaterial ? null : colors.bgSecondary,
      borderRadius: radius ?? AppRadii.standard.rLg,
      boxShadow: shadows.shadowSm,
      border: Border.all(color: AppGlass.highlight(colors)),
    );
  }
}

/// 磨砂玻璃面板（底部导航/弹层）：裁剪 + 背模糊 + 半透明底色 + 受光顶边。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    super.key,
    this.borderRadius,
    this.topHighlight = true,
    this.tint,
  });

  final Widget child;

  /// 裁剪圆角（弹层给顶部圆角；导航不给 = 直角矩形）。
  final BorderRadius? borderRadius;

  /// 是否画顶部 1px 受光边。
  final bool topHighlight;

  /// 覆盖磨砂底色（默认 bgSecondary × 材质透明度）。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final panel = Container(
      decoration: BoxDecoration(
        color:
            tint ??
            colors.bgSecondary.withValues(alpha: AppGlass.tintOpacity(colors)),
        borderRadius: borderRadius,
        border: topHighlight
            ? Border(top: BorderSide(color: AppGlass.highlight(colors)))
            : null,
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGlass.blurSigma,
          sigmaY: AppGlass.blurSigma,
        ),
        child: panel,
      ),
    );
  }
}

/// 主按钮玻璃光泽（叠层实现，不改变按钮本身的行为/尺寸/主题）：
/// 顶部 42% 高度叠一层白→透明渐变，模拟受光面。[enabled]=false 时
/// 原样返回（浅底非行动/禁用按钮不叠光泽——光泽=可行动暗示）。
class ButtonGloss extends StatelessWidget {
  const ButtonGloss({required this.child, this.enabled = true, super.key});

  /// 通常为 FilledButton（StadiumBorder 胶囊）。
  final Widget child;

  /// 是否叠光泽层。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const <double>[0, 0.42],
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.26),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

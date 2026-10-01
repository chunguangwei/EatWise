import 'package:flutter/material.dart';

/// 色彩 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.2。
///
/// 亮色色值取设计稿；暗色色值按 §2.7 推导规则占位〔假设〕，
/// 待设计侧输出暗色 Token 表后替换。
/// 2026-09-29 UI 重构（参考苹果健身/华为运动健康）：新增环图/图表强调色组
/// （ring*/chart*，加性不破坏既有命名）。
///
/// 2026-09-30 UI 换代 v2（参考华为运动健康「今日/我的/我的数据」实拍）：
/// 新增开口环仪表三色组（gauge*）、极简列表分隔线（divider）、
/// 图标徽标/轨道浅填充（fillSubtle）。同时加深 bgPrimary 灰度——华为观感的
/// 底层是「明确的灰底 + 纯白卡」对比，原 #F7F9F8 与白卡几乎无差，卡片浮不起来。
///
/// 2026-10-01 v1.16.0 全局设计感优化（对比度 P0 修复，用户拍板）：
/// 亮色 brandPrimary 轻盈绿 #3DBE8B → 沉稳绿 #2A9970（白字 CTA 2.35→3.4:1
/// 达大字级 AA；暗色 brandPrimary 保持 #3DBE8B 不动——深底上亮绿才够对比）；
/// 亮色 textSecondary #8A9694 → #5F6B69（白卡 3.06→5:1+ 达 AA）；新增
/// signalYellowText（黄灯徽标文字专用，#FFD24C 直接作文字仅 1.44:1）；
/// 暗色层级修复（bg 1.13:1 → ~1.5:1 + fillSubtle/divider 同步上浮）。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brandPrimary,
    required this.brandPrimaryPressed,
    required this.brandAccent,
    required this.signalRed,
    required this.signalYellow,
    required this.signalYellowText,
    required this.signalGreen,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.ringExercise,
    required this.ringStand,
    required this.ringMove,
    required this.chartPurple,
    required this.gaugeRed,
    required this.gaugeAmber,
    required this.gaugeBlue,
    required this.divider,
    required this.fillSubtle,
  });

  /// 沉稳绿（亮色 #2A9970 / 暗色 #3DBE8B）：品牌主色、断食进行态、CTA。
  final Color brandPrimary;

  /// 深林绿：按压态、强调。
  final Color brandPrimaryPressed;

  /// 暖阳橙：进食窗口、成就/打卡、FAB。
  final Color brandAccent;

  /// 活力珊瑚：红灯预警、营养超标。
  final Color signalRed;

  /// 提示黄：黄灯·适量提示（仅作色块/图标底，作文字色请用
  /// [signalYellowText]——本值上白卡仅 1.44:1 不可读）。
  final Color signalYellow;

  /// 黄灯徽标文字色（v1.16.0 新增）：signalYellow 的深色文字变体，
  /// 白卡上达 AA。
  final Color signalYellowText;

  /// 绿灯·达标（与主色同值，语义独立）。
  final Color signalGreen;

  /// 云白：页面背景。
  final Color bgPrimary;

  /// 卡片底。
  final Color bgSecondary;

  /// 墨黑：主文字。
  final Color textPrimary;

  /// 雾灰：次要文字、描边辅助。
  final Color textSecondary;

  /// 描边（与雾灰同源，透明度由组件定）。
  final Color border;

  /// 环图·活动/断食（与 brandPrimary 同值，独立语义——多环图专属，
  /// 改品牌色时环图配色可独立调整）。
  final Color ringExercise;

  /// 环图·站立/步数（青蓝，苹果站立环同族色）。
  final Color ringStand;

  /// 环图·消耗/进食（与 brandAccent 同值，独立语义）。
  final Color ringMove;

  /// 图表·紫（睡眠/心率/体重趋势类卡片强调色，华为迷你图表卡同族色）。
  final Color chartPurple;

  /// 开口环仪表·外环（华为「活动热量」红）。
  final Color gaugeRed;

  /// 开口环仪表·中环（华为「锻炼时长」琥珀黄）。
  final Color gaugeAmber;

  /// 开口环仪表·内环（华为「活动小时数」蓝）。
  final Color gaugeBlue;

  /// 极简列表分隔线（发丝线；比 border 更淡，仅用于同组行间）。
  final Color divider;

  /// 浅填充（圆形图标徽标底、进度轨道、分组间隔带）。
  final Color fillSubtle;

  /// 亮色主题 Token（设计稿 §2.2；v1.16.0 对比度修订见文件头注释）。
  static const AppColors light = AppColors(
    brandPrimary: Color(0xFF2A9970),
    brandPrimaryPressed: Color(0xFF1F7A5A),
    brandAccent: Color(0xFFFF9F45),
    signalRed: Color(0xFFFF6B6B),
    signalYellow: Color(0xFFFFD24C),
    signalYellowText: Color(0xFF8F6D1F),
    signalGreen: Color(0xFF2A9970),
    bgPrimary: Color(0xFFEFF2F1),
    bgSecondary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1E2A28),
    textSecondary: Color(0xFF5F6B69),
    border: Color(0xFF8A9694),
    ringExercise: Color(0xFF2A9970),
    ringStand: Color(0xFF4CA6FF),
    ringMove: Color(0xFFFF9F45),
    chartPurple: Color(0xFF8B7CF6),
    gaugeRed: Color(0xFFF5453F),
    gaugeAmber: Color(0xFFFFB225),
    gaugeBlue: Color(0xFF2E86FF),
    divider: Color(0xFFE4E9E8),
    fillSubtle: Color(0xFFF0F3F2),
  );

  /// 暗色主题 Token〔假设〕：按 §2.7 推导——背景反转为深灰绿系、
  /// 文字反转、signal* 保持色相提升亮度、品牌色保持亮绿。
  /// v1.16.0 层级修复：bgPrimary 压暗 + bgSecondary/fillSubtle/divider
  /// 上浮（原卡片底/页面底仅 1.13:1，「灰底白卡」语言暗色下塌掉）。
  /// 〔待外部确认〕设计侧输出暗色 Token 表后替换。
  static const AppColors dark = AppColors(
    brandPrimary: Color(0xFF3DBE8B), // 暗色保持亮绿（深底对比需要）
    brandPrimaryPressed: Color(0xFF5CD3A5), // 暗色按压态提亮〔假设〕
    brandAccent: Color(0xFFFF9F45), // 暖阳橙在深底上已达 AA，不变
    signalRed: Color(0xFFFF8585), // 同色相提亮〔假设〕
    signalYellow: Color(0xFFFFDB73), // 同色相提亮〔假设〕
    signalYellowText: Color(0xFFFFDB73), // 暗底上亮黄直接可读
    signalGreen: Color(0xFF3DBE8B),
    bgPrimary: Color(0xFF0C1110), // v1.16.0 压暗（原 #121817）
    bgSecondary: Color(0xFF222C29), // v1.16.0 上浮（原 #1B2422）
    textPrimary: Color(0xFFF7F9F8), // §2.7 给定推导值
    textSecondary: Color(0xFF8A9694), // 雾灰在深底上仍可用〔假设〕
    border: Color(0xFF8A9694),
    ringExercise: Color(0xFF3DBE8B), // 品牌色不变（§2.7）
    ringStand: Color(0xFF5CB2FF), // 青蓝暗色提亮〔假设〕
    ringMove: Color(0xFFFF9F45),
    chartPurple: Color(0xFFA39AFF), // 紫暗色提亮〔假设〕
    gaugeRed: Color(0xFFFF6059), // 开口环暗色提亮〔假设〕
    gaugeAmber: Color(0xFFFFC44D),
    gaugeBlue: Color(0xFF5CA0FF),
    divider: Color(0xFF37433F), // v1.16.0 上浮（原 #2A3634 几乎不可见）
    fillSubtle: Color(0xFF2B3734), // v1.16.0 上浮（与卡片底拉开一档）
  );

  @override
  AppColors copyWith({
    Color? brandPrimary,
    Color? brandPrimaryPressed,
    Color? brandAccent,
    Color? signalRed,
    Color? signalYellow,
    Color? signalYellowText,
    Color? signalGreen,
    Color? bgPrimary,
    Color? bgSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? ringExercise,
    Color? ringStand,
    Color? ringMove,
    Color? chartPurple,
    Color? gaugeRed,
    Color? gaugeAmber,
    Color? gaugeBlue,
    Color? divider,
    Color? fillSubtle,
  }) {
    return AppColors(
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandPrimaryPressed: brandPrimaryPressed ?? this.brandPrimaryPressed,
      brandAccent: brandAccent ?? this.brandAccent,
      signalRed: signalRed ?? this.signalRed,
      signalYellow: signalYellow ?? this.signalYellow,
      signalYellowText: signalYellowText ?? this.signalYellowText,
      signalGreen: signalGreen ?? this.signalGreen,
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      ringExercise: ringExercise ?? this.ringExercise,
      ringStand: ringStand ?? this.ringStand,
      ringMove: ringMove ?? this.ringMove,
      chartPurple: chartPurple ?? this.chartPurple,
      gaugeRed: gaugeRed ?? this.gaugeRed,
      gaugeAmber: gaugeAmber ?? this.gaugeAmber,
      gaugeBlue: gaugeBlue ?? this.gaugeBlue,
      divider: divider ?? this.divider,
      fillSubtle: fillSubtle ?? this.fillSubtle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandPrimaryPressed: Color.lerp(
        brandPrimaryPressed,
        other.brandPrimaryPressed,
        t,
      )!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      signalRed: Color.lerp(signalRed, other.signalRed, t)!,
      signalYellow: Color.lerp(signalYellow, other.signalYellow, t)!,
      signalYellowText: Color.lerp(
        signalYellowText,
        other.signalYellowText,
        t,
      )!,
      signalGreen: Color.lerp(signalGreen, other.signalGreen, t)!,
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t)!,
      bgSecondary: Color.lerp(bgSecondary, other.bgSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      ringExercise: Color.lerp(ringExercise, other.ringExercise, t)!,
      ringStand: Color.lerp(ringStand, other.ringStand, t)!,
      ringMove: Color.lerp(ringMove, other.ringMove, t)!,
      chartPurple: Color.lerp(chartPurple, other.chartPurple, t)!,
      gaugeRed: Color.lerp(gaugeRed, other.gaugeRed, t)!,
      gaugeAmber: Color.lerp(gaugeAmber, other.gaugeAmber, t)!,
      gaugeBlue: Color.lerp(gaugeBlue, other.gaugeBlue, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      fillSubtle: Color.lerp(fillSubtle, other.fillSubtle, t)!,
    );
  }
}

import 'package:flutter/material.dart';

/// 色彩 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.2。
///
/// 亮色色值取设计稿；暗色色值按 §2.7 推导规则占位〔假设〕，
/// 待设计侧输出暗色 Token 表后替换。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brandPrimary,
    required this.brandPrimaryPressed,
    required this.brandAccent,
    required this.signalRed,
    required this.signalYellow,
    required this.signalGreen,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  /// 轻盈绿：品牌主色、断食进行态、CTA。
  final Color brandPrimary;

  /// 沉稳绿：按压态、强调。
  final Color brandPrimaryPressed;

  /// 暖阳橙：进食窗口、成就/打卡、FAB。
  final Color brandAccent;

  /// 活力珊瑚：红灯预警、营养超标。
  final Color signalRed;

  /// 提示黄：黄灯·适量提示。
  final Color signalYellow;

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

  /// 亮色主题 Token（设计稿 §2.2）。
  static const AppColors light = AppColors(
    brandPrimary: Color(0xFF3DBE8B),
    brandPrimaryPressed: Color(0xFF2A9970),
    brandAccent: Color(0xFFFF9F45),
    signalRed: Color(0xFFFF6B6B),
    signalYellow: Color(0xFFFFD24C),
    signalGreen: Color(0xFF3DBE8B),
    bgPrimary: Color(0xFFF7F9F8),
    bgSecondary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1E2A28),
    textSecondary: Color(0xFF8A9694),
    border: Color(0xFF8A9694),
  );

  /// 暗色主题 Token〔假设〕：按 §2.7 推导——背景反转为深灰绿系、
  /// 文字反转、signal* 保持色相提升亮度、品牌色不变。
  /// 〔待外部确认〕设计侧输出暗色 Token 表后替换。
  static const AppColors dark = AppColors(
    brandPrimary: Color(0xFF3DBE8B), // 品牌色不变（§2.7）
    brandPrimaryPressed: Color(0xFF5CD3A5), // 暗色按压态提亮〔假设〕
    brandAccent: Color(0xFFFF9F45), // 暖阳橙在 #121817 上已达 AA，不变
    signalRed: Color(0xFFFF8585), // 同色相提亮〔假设〕
    signalYellow: Color(0xFFFFDB73), // 同色相提亮〔假设〕
    signalGreen: Color(0xFF3DBE8B),
    bgPrimary: Color(0xFF121817), // §2.7 给定推导值
    bgSecondary: Color(0xFF1B2422), // 卡片底〔假设〕：bgPrimary 上浮一档
    textPrimary: Color(0xFFF7F9F8), // §2.7 给定推导值
    textSecondary: Color(0xFF8A9694), // 雾灰在深底上仍可用〔假设〕
    border: Color(0xFF8A9694),
  );

  @override
  AppColors copyWith({
    Color? brandPrimary,
    Color? brandPrimaryPressed,
    Color? brandAccent,
    Color? signalRed,
    Color? signalYellow,
    Color? signalGreen,
    Color? bgPrimary,
    Color? bgSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
  }) {
    return AppColors(
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandPrimaryPressed: brandPrimaryPressed ?? this.brandPrimaryPressed,
      brandAccent: brandAccent ?? this.brandAccent,
      signalRed: signalRed ?? this.signalRed,
      signalYellow: signalYellow ?? this.signalYellow,
      signalGreen: signalGreen ?? this.signalGreen,
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
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
      signalGreen: Color.lerp(signalGreen, other.signalGreen, t)!,
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t)!,
      bgSecondary: Color.lerp(bgSecondary, other.bgSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

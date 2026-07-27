import 'package:flutter/material.dart';

/// 排版 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.3。
///
/// 行高固定到每个 Token（1.4–1.5），禁止组件内另写行高。
/// 字体回退链：Inter（西文/数字）→ PingFang SC / Noto Sans SC（中文），
/// 字体文件打包前系统自动回退〔假设：字体随包内置为后续任务〕。
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.textXs,
    required this.textSm,
    required this.textBase,
    required this.textLg,
    required this.textXl,
    required this.text2xl,
    required this.text3xl,
    required this.textH1,
    required this.textTimer,
  });

  /// 12pt：徽章、辅助标注。
  final TextStyle textXs;

  /// 14pt：辅助文字、信号卡营养名（正文最小值）。
  final TextStyle textSm;

  /// 16pt：正文、按钮。
  final TextStyle textBase;

  /// 18pt：强调正文。
  final TextStyle textLg;

  /// 20pt Medium：H2。
  final TextStyle textXl;

  /// 24pt Medium：区块标题。
  final TextStyle text2xl;

  /// 30pt Semibold：大数字（营养值）。
  final TextStyle text3xl;

  /// 28pt Semibold：页面主标题〔待外部确认：是否并入字号阶梯〕。
  final TextStyle textH1;

  /// 48pt Bold：断食倒计时数字，仅数字场景。
  final TextStyle textTimer;

  /// 全局字体回退链（设计稿 2.3 / i18n 规格 §6.3）。
  static const List<String> fontFamilyFallback = <String>[
    'Inter',
    'PingFang SC',
    'Noto Sans SC',
  ];

  static TextStyle _style(double fontSize, FontWeight weight, double height) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  /// 默认文字样式集（字色由组件/主题给定，不在 Token 内固化）。
  static final AppTextStyles standard = AppTextStyles(
    textXs: _style(12, FontWeight.w400, 1.4),
    textSm: _style(14, FontWeight.w400, 1.4),
    textBase: _style(16, FontWeight.w400, 1.5),
    textLg: _style(18, FontWeight.w400, 1.5),
    textXl: _style(20, FontWeight.w500, 1.4),
    text2xl: _style(24, FontWeight.w500, 1.4),
    text3xl: _style(30, FontWeight.w600, 1.4),
    textH1: _style(28, FontWeight.w600, 1.4),
    textTimer: _style(48, FontWeight.w700, 1.1),
  );

  @override
  AppTextStyles copyWith({
    TextStyle? textXs,
    TextStyle? textSm,
    TextStyle? textBase,
    TextStyle? textLg,
    TextStyle? textXl,
    TextStyle? text2xl,
    TextStyle? text3xl,
    TextStyle? textH1,
    TextStyle? textTimer,
  }) {
    return AppTextStyles(
      textXs: textXs ?? this.textXs,
      textSm: textSm ?? this.textSm,
      textBase: textBase ?? this.textBase,
      textLg: textLg ?? this.textLg,
      textXl: textXl ?? this.textXl,
      text2xl: text2xl ?? this.text2xl,
      text3xl: text3xl ?? this.text3xl,
      textH1: textH1 ?? this.textH1,
      textTimer: textTimer ?? this.textTimer,
    );
  }

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return AppTextStyles(
      textXs: TextStyle.lerp(textXs, other.textXs, t)!,
      textSm: TextStyle.lerp(textSm, other.textSm, t)!,
      textBase: TextStyle.lerp(textBase, other.textBase, t)!,
      textLg: TextStyle.lerp(textLg, other.textLg, t)!,
      textXl: TextStyle.lerp(textXl, other.textXl, t)!,
      text2xl: TextStyle.lerp(text2xl, other.text2xl, t)!,
      text3xl: TextStyle.lerp(text3xl, other.text3xl, t)!,
      textH1: TextStyle.lerp(textH1, other.textH1, t)!,
      textTimer: TextStyle.lerp(textTimer, other.textTimer, t)!,
    );
  }
}

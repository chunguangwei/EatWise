import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 应用主题装配：亮/暗/跟随系统（设计稿 §2.1 / §2.7）。
///
/// 用法：`AppTheme.light()` / `AppTheme.dark()`，外层 `themeMode: ThemeMode.system`。
///
/// 2026-10-01 v1.16.0 主题层收口（华为运动健康 + 苹果简约）：
/// 此前只配了 switchTheme——按钮 81 处 styleFrom 重复造轮子、二级页
/// AppBar 白底与主 tab 灰底断层、弹层圆角 M3 默认 28 vs 卡片 20 分裂、
/// SnackBar 贴底长条。现统一收口到全局组件主题：
/// - AppBar：灰底零阴影左对齐 textXl（华为/苹果「页内大标题」语言）；
/// - 按钮双级：FilledButton 品牌绿实心 48px 胶囊（页面级主行动）/
///   OutlinedButton 绿描边 48px 胶囊（次级）；56px 强转化胶囊仅首页等
///   个别调用点显式覆盖；
/// - 弹窗/弹层圆角统一 rLg=20；SnackBar 悬浮 rMd 胶囊；
/// - 输入框填充 + rMd 描边（portion_input 等显式装饰不受影响）。
abstract final class AppTheme {
  static ThemeData light() {
    const colors = AppColors.light;
    return _base(colors, AppShadows.light, Brightness.light);
  }

  static ThemeData dark() {
    const colors = AppColors.dark;
    return _base(colors, AppShadows.dark, Brightness.dark);
  }

  static ThemeData _base(
    AppColors colors,
    AppShadows shadows,
    Brightness brightness,
  ) {
    final textStyles = AppTextStyles.standard;
    const radii = AppRadii.standard;
    final buttonTextStyle = textStyles.textBase.copyWith(
      fontWeight: FontWeight.w600,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bgPrimary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.brandPrimary,
        onPrimary: Colors.white,
        secondary: colors.brandAccent,
        onSecondary: colors.textPrimary,
        error: colors.signalRed,
        onError: Colors.white,
        surface: colors.bgSecondary,
        onSurface: colors.textPrimary,
      ),
      extensions: <ThemeExtension<dynamic>>[colors, textStyles, radii, shadows],
      // AppBar 全局统一：灰底零阴影、左对齐（华为/苹果语言；M3 默认
      // iOS 居中 / Android 左对齐的平台分裂消除）、滚动不变色。
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textStyles.textXl.copyWith(color: colors.textPrimary),
      ),
      // 主行动按钮：品牌绿实心 48px 胶囊（页面级基准；56px 强转化位
      // 由调用点显式覆盖）。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.brandPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.fillSubtle,
          disabledForegroundColor: colors.textSecondary,
          minimumSize: const Size(64, AppSpacing.s12),
          shape: const StadiumBorder(),
          textStyle: buttonTextStyle,
        ),
      ),
      // 次级行动按钮：品牌绿描边 48px 胶囊（连胜卡「去补签」语言）。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.brandPrimary,
          disabledForegroundColor: colors.textSecondary,
          side: BorderSide(color: colors.brandPrimary),
          minimumSize: const Size(64, AppSpacing.s12),
          shape: const StadiumBorder(),
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.brandPrimary),
      ),
      // 弹窗/弹层圆角与卡片统一（修 M3 默认 28 vs rLg 20 分裂）。
      dialogTheme: DialogThemeData(
        backgroundColor: colors.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: radii.rLg),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: radii.rLg.topLeft),
        ),
      ),
      // SnackBar 悬浮胶囊（苹果式反馈条，替代贴底长条）。
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radii.rMd),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      // 输入框：填充 + rMd 描边（华为填充圆角语言；focus 品牌绿 2px）。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.bgSecondary,
        border: OutlineInputBorder(
          borderRadius: radii.rMd,
          borderSide: BorderSide(color: colors.border.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radii.rMd,
          borderSide: BorderSide(color: colors.border.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radii.rMd,
          borderSide: BorderSide(color: colors.brandPrimary, width: 2),
        ),
      ),
      // 开关全局统一（走查 B-2）：开启品牌绿填充/白滑块；关闭雾灰浅轨 +
      // 雾灰滑块、无描边（此前依赖 M3 默认，关闭态黑线框与设置页观感割裂）。
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors
                    .white // 与 colorScheme.onPrimary 同源
              : colors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.brandPrimary
              : colors.textSecondary.withValues(alpha: 0.24),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}

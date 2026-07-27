import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 应用主题装配：亮/暗/跟随系统（设计稿 §2.1 / §2.7）。
///
/// 用法：`AppTheme.light()` / `AppTheme.dark()`，外层 `themeMode: ThemeMode.system`。
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
      extensions: <ThemeExtension<dynamic>>[
        colors,
        AppTextStyles.standard,
        AppRadii.standard,
        shadows,
      ],
    );
  }
}

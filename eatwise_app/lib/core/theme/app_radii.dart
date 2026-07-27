import 'package:flutter/material.dart';

/// 圆角 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.4。
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.rSm,
    required this.rMd,
    required this.rLg,
    required this.rFull,
  });

  /// 6：小标签、徽章。
  final BorderRadius rSm;

  /// 12：按钮、输入框。
  final BorderRadius rMd;

  /// 16：卡片。
  final BorderRadius rLg;

  /// 9999：计时环、FAB、胶囊。
  final BorderRadius rFull;

  static const AppRadii standard = AppRadii(
    rSm: BorderRadius.all(Radius.circular(6)),
    rMd: BorderRadius.all(Radius.circular(12)),
    rLg: BorderRadius.all(Radius.circular(16)),
    rFull: BorderRadius.all(Radius.circular(9999)),
  );

  @override
  AppRadii copyWith({
    BorderRadius? rSm,
    BorderRadius? rMd,
    BorderRadius? rLg,
    BorderRadius? rFull,
  }) {
    return AppRadii(
      rSm: rSm ?? this.rSm,
      rMd: rMd ?? this.rMd,
      rLg: rLg ?? this.rLg,
      rFull: rFull ?? this.rFull,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      rSm: BorderRadius.lerp(rSm, other.rSm, t)!,
      rMd: BorderRadius.lerp(rMd, other.rMd, t)!,
      rLg: BorderRadius.lerp(rLg, other.rLg, t)!,
      rFull: BorderRadius.lerp(rFull, other.rFull, t)!,
    );
  }
}

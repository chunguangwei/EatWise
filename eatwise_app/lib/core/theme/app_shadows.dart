import 'package:flutter/material.dart';

/// 阴影 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.5。
///
/// 参数为建议值〔待外部确认〕；暗色下透明度减半（§2.5 约束）。
/// Android 不使用 elevation 系统阴影，统一走 Token。
@immutable
class AppShadows extends ThemeExtension<AppShadows> {
  const AppShadows({
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
  });

  /// 卡片。
  final List<BoxShadow> shadowSm;

  /// 浮层、FAB。
  final List<BoxShadow> shadowMd;

  /// 弹窗。
  final List<BoxShadow> shadowLg;

  static const Color _shadowColor = Color(0xFF1E2A28); // 墨黑

  /// 亮色阴影（§2.5 建议参数；2026-09-29 UI 重构调柔调扩散——更大 blur、
  /// 更低 alpha，对齐华为白卡「浮起但不割裂」的观感）。
  static const AppShadows light = AppShadows(
    shadowSm: <BoxShadow>[
      BoxShadow(offset: Offset(0, 2), blurRadius: 12, color: Color(0x0F1E2A28)),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(offset: Offset(0, 6), blurRadius: 24, color: Color(0x141E2A28)),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 40,
        color: Color(0x1F1E2A28),
      ),
    ],
  );

  /// 暗色阴影：透明度减半（§2.5）〔待外部确认〕。
  static const AppShadows dark = AppShadows(
    shadowSm: <BoxShadow>[
      BoxShadow(offset: Offset(0, 2), blurRadius: 12, color: Color(0x081E2A28)),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(offset: Offset(0, 6), blurRadius: 24, color: Color(0x0A1E2A28)),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 40,
        color: Color(0x101E2A28),
      ),
    ],
  );

  /// 供后续按基准色重建（当前固定墨黑）。
  static Color get baseColor => _shadowColor;

  @override
  AppShadows copyWith({
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
  }) {
    return AppShadows(
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
    );
  }

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) return this;
    return AppShadows(
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
      shadowLg: BoxShadow.lerpList(shadowLg, other.shadowLg, t)!,
    );
  }
}

import 'package:flutter/material.dart';

/// 阴影 Token（ThemeExtension），映射《规格-设计交付规范与全局UI四态》§2.5。
///
/// 参数为建议值〔待外部确认〕。Android 不使用 elevation 系统阴影，统一走 Token。
/// 2026-10-01 v1.16.0：删 shadowLg（0 引用死令牌，弹窗/弹层走 dialogTheme/
/// bottomSheetTheme 圆角+M3 elevation）；分工钉死——shadowSm=内容卡基准、
/// shadowMd=浮层变体（记录页选中结果卡等需要「浮于卡片之上」的场景）。
/// 暗色 alpha 翻倍（原减半口径下 3%–6% ≈ 不可见，暗色卡片浮不起来）。
@immutable
class AppShadows extends ThemeExtension<AppShadows> {
  const AppShadows({required this.shadowSm, required this.shadowMd});

  /// 卡片（内容卡唯一基准阴影）。
  final List<BoxShadow> shadowSm;

  /// 浮层变体（需浮于卡片之上的选中结果卡、FAB）。
  final List<BoxShadow> shadowMd;

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
  );

  /// 暗色阴影：alpha 与亮色持平（v1.16.0——原减半口径下 ≈ 不可见，
  /// 叠加暗色卡片底与页面底的微小亮度差后层级完全消失）。
  static const AppShadows dark = AppShadows(
    shadowSm: <BoxShadow>[
      BoxShadow(offset: Offset(0, 2), blurRadius: 12, color: Color(0x1F1E2A28)),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(offset: Offset(0, 6), blurRadius: 24, color: Color(0x291E2A28)),
    ],
  );

  /// 供后续按基准色重建（当前固定墨黑）。
  static Color get baseColor => _shadowColor;

  @override
  AppShadows copyWith({List<BoxShadow>? shadowSm, List<BoxShadow>? shadowMd}) {
    return AppShadows(
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
    );
  }

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) return this;
    return AppShadows(
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
    );
  }
}

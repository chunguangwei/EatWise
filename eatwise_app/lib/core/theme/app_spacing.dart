/// 间距 Token（4pt 阶梯），映射《规格-设计交付规范与全局UI四态》§2.6。
///
/// 普通常量类（非 ThemeExtension）：`AppSpacing.s4`。
/// 代码层禁止裸间距数字。
abstract final class AppSpacing {
  /// 4：图标与文字间隙。
  static const double s1 = 4;

  /// 8：紧凑元素间距。
  static const double s2 = 8;

  /// 12：卡片内行距。
  static const double s3 = 12;

  /// 16：卡片内边距、栅格 gutter、安全边距。
  static const double s4 = 16;

  /// 24：区块间距。
  static const double s6 = 24;

  /// 32：页面区段。
  static const double s8 = 32;

  /// 48：大留白、按钮高度基准。
  static const double s12 = 48;

  /// 64：首屏大留白。
  static const double s16 = 64;
}

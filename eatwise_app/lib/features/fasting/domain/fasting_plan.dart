/// 断食方案（《规格-M2》§3.1：窗口配置存「本地墙钟表达」）。
///
/// 窗口起止以「本地墙钟时间（HH:mm）+ 24h 周期」表达，落地时经时区换算为
/// UTC 锚点（§3.2），跨午夜进食窗口（eatEnd ≤ eatStart）做防御处理。

library;

final class FastingPlan {
  const FastingPlan({
    required this.id,
    required this.eatStartMinutes,
    required this.eatEndMinutes,
  });

  /// 16:8，进食窗口 12:00–20:00（D-03 跳过问卷兜底方案）。
  static const FastingPlan plan16x8 = FastingPlan(
    id: '16:8',
    eatStartMinutes: 12 * 60,
    eatEndMinutes: 20 * 60,
  );

  /// 14:10，进食窗口 10:00–20:00（D-03 备选/推荐）。
  static const FastingPlan plan14x10 = FastingPlan(
    id: '14:10',
    eatStartMinutes: 10 * 60,
    eatEndMinutes: 20 * 60,
  );

  /// 方案标识（内部口径），如 `16:8`；自定义窗口带锚点后缀 `16:8@09:00`
  /// （`@HH:mm` = 进食窗口开始锚点，`window_rules.buildWindow` 生成，
  /// 供同步/落盘稳定标识，不是给用户看的）。
  final String id;

  /// 面向用户的方案类型名（去掉 `@HH:mm` 锚点后缀，如 `14:10@09:00` →
  /// `14:10`）：锚点即进食窗口开始时间，界面已单独展示窗口区间，原样
  /// 展示 id 会让用户看不懂（真机走查反馈）。展示一律用本 getter。
  String get planTypeId => id.split('@').first;

  /// 进食窗口开始：本地墙钟，距当日 0:00 的分钟数（如 12:00 → 720）。
  final int eatStartMinutes;

  /// 进食窗口结束：本地墙钟分钟数（如 20:00 → 1200）。
  /// 若 ≤ eatStartMinutes 视为跨午夜进食窗口（§3.2 防御）。
  final int eatEndMinutes;

  /// 进食窗口时长（分钟）；跨午夜时 +24h。
  int get eatWindowMinutes => eatEndMinutes > eatStartMinutes
      ? eatEndMinutes - eatStartMinutes
      : eatEndMinutes - eatStartMinutes + 24 * 60;

  /// 断食窗口时长（分钟）= 24h 补集。
  int get fastWindowMinutes => 24 * 60 - eatWindowMinutes;

  @override
  bool operator ==(Object other) =>
      other is FastingPlan &&
      other.id == id &&
      other.eatStartMinutes == eatStartMinutes &&
      other.eatEndMinutes == eatEndMinutes;

  @override
  int get hashCode => Object.hash(id, eatStartMinutes, eatEndMinutes);

  @override
  String toString() => 'FastingPlan($id, eat $eatStartMinutes–$eatEndMinutes)';
}

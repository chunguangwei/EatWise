/// 断食计时状态机类型定义（《规格-M2 断食计时状态机与边界用例》§2）。
///
/// 全部为纯 Dart，不依赖 Flutter Widget；时间戳一律 UTC epoch 秒（D-07）。

/// 应用级当前状态（§2.1，单例全局唯一当前值）。
library;

enum FastingState {
  /// 未启动任何断食方案。
  noPlan,

  /// 处于进食窗口内。
  eating,

  /// 处于断食窗口内，未发生延长。
  fasting,

  /// 处于断食窗口内，本周期已执行过 ≥1 次延长。
  fastingExtended,
}

/// FastCycle 实体级终态（§2.1，写入 FastingRecord 后不可变）。
enum CycleResult {
  /// 进食窗口到点自然开启，完整走完。✅ 达标
  completedOnTime,

  /// 手动提前破窗，提前量 ≤ 容差（D-08）。✅ 达标
  completedEarlyPass,

  /// 延长后走完，或延长后手动结束且实际断食时长 ≥ 原计划时长（D-08）。✅ 达标
  completedExtended,

  /// 手动提前破窗，提前量 > 容差（D-08）。❌ 不达标
  brokenEarly,

  /// 归属日已过但该周期无任何完成/破窗事件（§6-B12〔假设〕：MVP 下仅覆盖
  /// 「无周期覆盖的自然日」，窗口迁移由锚点推导，不依赖用户操作）。
  missed,
}

/// 事件枚举（§2.2）。
enum FastingEvent {
  /// 计划（或延长后）的进食窗口开始时刻到达。
  eatWindowStartDue,

  /// 进食窗口结束时刻到达（= 新断食开始）。
  eatWindowEndDue,

  /// 用户点「结束断食」。
  manualEndFast,

  /// 用户点「延长」。
  manualExtend,

  /// 用户更换方案/窗口（次日 0:00 本地生效，D-06）。
  planChange,

  /// 新方案生效时刻（本地 0:00）到达。
  planActivate,

  /// 系统时区变化。
  timezoneChange,

  /// 系统时间被回拨/拨快。
  clockChanged,

  /// App 启动/回前台（恢复事件，按锚点重算）。
  appForeground,
}

/// 周期关闭原因（§3.3 伪代码 `reason`）。
enum CloseReason {
  /// 进食窗口（计划或延长后锚点）到点。
  windowStartDue,

  /// 手动「结束断食」。
  manualEnd,
}

/// 本地自然日（某时区下的 y/m/d），归属日计算的中间表示（D-07）。
final class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// 加 n 天（经 UTC 日期算术，与时区无关）。
  LocalDate addDays(int n) {
    final dt = DateTime.utc(year, month, day + n);
    return LocalDate(dt.year, dt.month, dt.day);
  }

  /// `yyyy-MM-dd`（FastingRecord.date 存储格式）。
  String toIsoString() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIsoString();
}

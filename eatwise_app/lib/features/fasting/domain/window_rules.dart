/// 自定义进食窗口规则（进食窗口自选：时长 6h/8h/10h + 自定义起止，允许跨午夜）。
///
/// 纯函数：无 I/O、无时钟；同输入必同输出。planType 由进食时长派生
/// （10h→14:10、8h→16:8、6h→18:6，即服务端 /fasting-plans/current 契约：
/// 窗口时长必须等于 24h − planType 禁食时长）。
library;

import 'package:eatwise/features/fasting/domain/fasting_plan.dart';

/// 方案类型字符串（`14:10` / `16:8` / `18:6`）。
///
/// [eatingHours] 非 6/8/10 抛 [ArgumentError]（服务端会按同一规则 400）。
String planTypeForEatingHours(int eatingHours) {
  return switch (eatingHours) {
    10 => '14:10',
    8 => '16:8',
    6 => '18:6',
    _ => throw ArgumentError.value(
      eatingHours,
      'eatingHours',
      '进食时长只支持 6/8/10 小时',
    ),
  };
}

/// 墙钟分钟数 → `HH:mm`（如 540 → `09:00`）。
String formatClock(int minutesOfDay) {
  final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minutesOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// 进食窗口标签 `HH:mm–HH:mm`（跨午夜时 end < start，原样展示）。
String formatWindow(int start, int end) =>
    '${formatClock(start)}–${formatClock(end)}';

/// 两个窗口是否等价（只比起止墙钟分钟，不比方案 id——同窗口的方案 id 可能
/// 带 `@HH:mm` 后缀）。换方案判定（D-06）与「换同方案直接重写」均以此为准。
bool sameWindow(int startA, int endA, int startB, int endB) =>
    startA == startB && endA == endB;

/// 自定义窗口草稿（编辑器 → 控制器 → 方案落盘/上行的中间值对象）。
final class FastingWindowDraft {
  const FastingWindowDraft({
    required this.eatingHours,
    required this.planType,
    required this.startMinutes,
    required this.endMinutes,
    required this.planId,
  });

  /// 进食时长（小时，6/8/10）。
  final int eatingHours;

  /// 派生方案类型（`14:10` / `16:8` / `18:6`）。
  final String planType;

  /// 进食窗口开始：本地墙钟分钟数。
  final int startMinutes;

  /// 进食窗口结束：本地墙钟分钟数（跨午夜时 < [startMinutes]）。
  final int endMinutes;

  /// 方案 id：`24-h:h@HH:mm`（如 `16:8@09:00`）。
  final String planId;

  /// 禁食时长（小时）= 24 − 进食时长。
  int get fastingHours => 24 - eatingHours;

  /// 转为计时引擎的 [FastingPlan]。
  FastingPlan toFastingPlan() => FastingPlan(
    id: planId,
    eatStartMinutes: startMinutes,
    eatEndMinutes: endMinutes,
  );

  @override
  bool operator ==(Object other) =>
      other is FastingWindowDraft &&
      other.eatingHours == eatingHours &&
      other.planType == planType &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.planId == planId;

  @override
  int get hashCode =>
      Object.hash(eatingHours, planType, startMinutes, endMinutes, planId);

  @override
  String toString() =>
      'FastingWindowDraft($planId, eat $startMinutes–$endMinutes)';
}

/// 构造自定义进食窗口草稿。
///
/// - [eatingHours] ∈ {6, 8, 10}，否则抛 [ArgumentError]；
/// - [startMinutes] ∈ [0, 1440)，否则抛 [ArgumentError]；
/// - end = (start + hours×60) mod 1440（自动跨午夜，如 23:00 + 10h → 09:00）；
/// - planId = `24-h:h@HH:mm`（planType 由时长派生，`16:8@09:00` 式）。
FastingWindowDraft buildWindow({
  required int eatingHours,
  required int startMinutes,
}) {
  final planType = planTypeForEatingHours(eatingHours);
  if (startMinutes < 0 || startMinutes >= 24 * 60) {
    throw ArgumentError.value(
      startMinutes,
      'startMinutes',
      '开始时间须在 0..1439 分钟之间',
    );
  }
  final endMinutes = (startMinutes + eatingHours * 60) % (24 * 60);
  return FastingWindowDraft(
    eatingHours: eatingHours,
    planType: planType,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    planId: '$planType@${formatClock(startMinutes)}',
  );
}

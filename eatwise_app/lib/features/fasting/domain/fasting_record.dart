import 'package:eatwise/features/fasting/domain/fasting_types.dart';

/// 断食记录（§3.3 `close_cycle` 输出，写入后不可变）。
///
/// 归属日冻结规则（§3.3）：在进食窗口开始时刻（周期关闭时）计算并写入，
/// 此后不再因时区变化、时间回拨而改写（D-07）。
final class FastingRecord {
  const FastingRecord({
    required this.date,
    required this.startUtc,
    required this.endUtc,
    required this.actualSec,
    required this.plannedSec,
    required this.extendedMinutes,
    required this.result,
    required this.qualified,
  });

  /// 打卡归属日（`yyyy-MM-dd`）= 结束该周期的进食窗口开始时刻在
  /// 该时刻设备时区下渲染出的自然日（D-07 / §3.3）。冻结不改写。
  final String date;

  /// 断食开始锚点（UTC epoch 秒）。
  final int startUtc;

  /// 实际结束锚点（UTC epoch 秒）。
  final int endUtc;

  /// 实际断食时长（秒）。
  final int actualSec;

  /// 计划断食时长（秒，含延长）。
  final int plannedSec;

  /// 本周期累计延长分钟数。
  final int extendedMinutes;

  /// 终态。
  final CycleResult result;

  /// 是否达标（D-08，streak 唯一口径，D-12）。
  final bool qualified;

  @override
  String toString() =>
      'FastingRecord(date=$date, result=$result, qualified=$qualified, '
      'actual=${actualSec}s)';
}

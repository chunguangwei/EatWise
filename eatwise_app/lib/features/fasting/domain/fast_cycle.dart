import 'package:eatwise/features/fasting/domain/fasting_types.dart';

/// 断食周期实体（《规格-M2》§1：一次断食的完整生命周期）。
///
/// 定义（§3.2）：`FastCycle(n) = [eatEndUtc(n-1), eatStartUtc(n))`，
/// 即「昨晚进食结束 → 今天进食开始」。全部锚点为 UTC epoch 秒（D-07）。
final class FastCycle {
  const FastCycle({
    required this.startUtc,
    required this.plannedEndUtc,
    required this.eatWindowEndUtc,
    this.extendedMinutes = 0,
  });

  /// 断食开始锚点 = 前一进食窗口结束（UTC epoch 秒）。
  final int startUtc;

  /// 计划进食窗口开始锚点（**含延长**，UTC epoch 秒）。
  final int plannedEndUtc;

  /// 本周期结束后的当日进食窗口结束锚点（随延长同步后移，D-10；
  /// 提前破窗时不后移〔假设〕，见 §2.3-T3）。
  final int eatWindowEndUtc;

  /// 本周期累计延长分钟数（步进 30，上限 240，D-10/§4.3）。
  final int extendedMinutes;

  /// 当前应用级状态：发生过延长 → [FastingState.fastingExtended]。
  FastingState get state =>
      extendedMinutes > 0 ? FastingState.fastingExtended : FastingState.fasting;

  /// 计划断食总时长（秒，含延长）。
  int get plannedSec => plannedEndUtc - startUtc;

  /// 原计划断食时长（秒，不含延长）。
  int get plannedOriginalSec => plannedSec - extendedMinutes * 60;

  FastCycle copyWith({
    int? startUtc,
    int? plannedEndUtc,
    int? eatWindowEndUtc,
    int? extendedMinutes,
  }) {
    return FastCycle(
      startUtc: startUtc ?? this.startUtc,
      plannedEndUtc: plannedEndUtc ?? this.plannedEndUtc,
      eatWindowEndUtc: eatWindowEndUtc ?? this.eatWindowEndUtc,
      extendedMinutes: extendedMinutes ?? this.extendedMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FastCycle &&
      other.startUtc == startUtc &&
      other.plannedEndUtc == plannedEndUtc &&
      other.eatWindowEndUtc == eatWindowEndUtc &&
      other.extendedMinutes == extendedMinutes;

  @override
  int get hashCode =>
      Object.hash(startUtc, plannedEndUtc, eatWindowEndUtc, extendedMinutes);

  @override
  String toString() =>
      'FastCycle(start=$startUtc, plannedEnd=$plannedEndUtc, '
      'eatEnd=$eatWindowEndUtc, ext=${extendedMinutes}min)';
}

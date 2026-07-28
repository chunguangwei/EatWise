import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:timezone/timezone.dart' as tz;

/// 断食窗口提醒的通知计划（纯逻辑，《规格-M2 断食计时状态机》§7，D-09）。
///
/// 只依赖 fasting domain 的锚点函数与 timezone 包，不依赖 Flutter，
/// 可全量单测。时间戳一律 UTC epoch 秒（D-07）。

/// 三类窗口提醒（§7.1 通知排程表）。
enum FastingNotificationKind {
  /// 进食窗口开始前提醒（默认提前 15min，设置可调，D-09）。
  eatSoon,

  /// 进食窗口到点（含延长后新锚点）。
  eatStart,

  /// 断食窗口开始（= 进食窗口结束）到点。
  fastStart,
}

/// 计划中的一条通知（尚未落地为平台排程）。
final class PlannedFastingNotification {
  const PlannedFastingNotification({
    required this.kind,
    required this.id,
    required this.triggerAtUtcSec,
    this.attributionDate,
  });

  /// 通知类型。
  final FastingNotificationKind kind;

  /// 通知 id（int32，由触发时刻+类型推导，重排时可复现）。
  final int id;

  /// 触发时刻（UTC epoch 秒）。
  final int triggerAtUtcSec;

  /// 打卡归属日（D-07：进食窗口开始时刻的本地自然日），
  /// 仅 [FastingNotificationKind.eatStart] 文案需要（「本次断食计入 X 月 X 日」）。
  final LocalDate? attributionDate;

  @override
  bool operator ==(Object other) =>
      other is PlannedFastingNotification &&
      other.kind == kind &&
      other.id == id &&
      other.triggerAtUtcSec == triggerAtUtcSec &&
      other.attributionDate == attributionDate;

  @override
  int get hashCode => Object.hash(kind, id, triggerAtUtcSec, attributionDate);

  @override
  String toString() => 'PlannedFastingNotification($kind, $triggerAtUtcSec)';
}

/// 通知 id：触发分钟 × 10 + 类型序号。
///
/// int32 上限对应约公元 2378 年，安全；三类通知触发分钟两两不同
/// （eatSoon 早于 eatStart 一个提前量），故窗口内唯一。
int fastingNotificationId(int triggerAtUtcSec, FastingNotificationKind kind) =>
    (triggerAtUtcSec ~/ 60) * 10 + kind.index;

/// 生成未来 [horizonSec] 内的通知计划（§7.2.2：每次重排为未来 48h 内
/// 全部触发点，每周期 3 条 × 2 天 ≈ 6 条，远低于 iOS 64 条上限）。
///
/// - [plan]：断食方案（本地墙钟窗口，§3.1）；
/// - [nowUtcSec]：当前时刻（注入时钟，便于测试）；
/// - [location]：设备当前时区；
/// - [eatSoonLeadSec]：进食开始提前量（D-09 默认 15min，设置可调）；
/// - [extensionMinutes]：当前 FastCycle 累计延长（D-10）。延长只后移
///   「当前周期目标日」的进食开始与进食结束锚点（T5：进食窗口时长不压缩），
///   其余周期锚点不受影响。
///
/// 返回按触发时刻升序的列表；仅含 `(now, now + horizon]` 内的触发点
/// （48h 窗口裁剪，§7.2.2）。
List<PlannedFastingNotification> buildFastingNotificationPlan({
  required FastingPlan plan,
  required int nowUtcSec,
  required tz.Location location,
  int eatSoonLeadSec = 15 * 60,
  int horizonSec = 48 * 3600,
  int extensionMinutes = 0,
}) {
  final today = localDateOf(nowUtcSec, location);

  // 当前断食周期的目标日 = now 之后第一个进食开始锚点所在的本地自然日；
  // 延长只作用于该日锚点（T5/T6），次日及以后周期不继承（§4.3）。
  LocalDate? extensionTargetDate;
  if (extensionMinutes > 0) {
    for (
      var offset = -1;
      offset <= 2 && extensionTargetDate == null;
      offset++
    ) {
      final date = today.addDays(offset);
      if (anchorsFor(plan, date, location).eatStartUtc > nowUtcSec) {
        extensionTargetDate = date;
      }
    }
  }

  final items = <PlannedFastingNotification>[];
  for (var offset = -1; offset <= 2; offset++) {
    final date = today.addDays(offset);
    var anchors = anchorsFor(plan, date, location);
    if (extensionTargetDate != null && date == extensionTargetDate) {
      final shiftSec = extensionMinutes * 60;
      anchors = (
        eatStartUtc: anchors.eatStartUtc + shiftSec,
        eatEndUtc: anchors.eatEndUtc + shiftSec,
      );
    }

    void add(FastingNotificationKind kind, int triggerAtUtcSec) {
      if (triggerAtUtcSec <= nowUtcSec ||
          triggerAtUtcSec > nowUtcSec + horizonSec) {
        return;
      }
      items.add(
        PlannedFastingNotification(
          kind: kind,
          id: fastingNotificationId(triggerAtUtcSec, kind),
          triggerAtUtcSec: triggerAtUtcSec,
          attributionDate: kind == FastingNotificationKind.eatStart
              // D-07：归属日 = 进食窗口开始时刻的本地自然日（预计算值，
              // 允许随时区变化更新，周期关闭时由状态机冻结）。
              ? localDateOf(triggerAtUtcSec, location)
              : null,
        ),
      );
    }

    add(FastingNotificationKind.eatSoon, anchors.eatStartUtc - eatSoonLeadSec);
    add(FastingNotificationKind.eatStart, anchors.eatStartUtc);
    add(FastingNotificationKind.fastStart, anchors.eatEndUtc);
  }

  items.sort((a, b) {
    final byTime = a.triggerAtUtcSec.compareTo(b.triggerAtUtcSec);
    return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
  });
  return items;
}

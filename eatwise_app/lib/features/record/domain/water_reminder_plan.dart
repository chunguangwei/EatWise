import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:timezone/timezone.dart' as tz;

/// 喝水提醒计划（纯逻辑，无 Flutter 依赖，可全量单测）。
///
/// 口径：
/// - 「非断食期间」= 进食窗口内提醒（断食中不提醒，与 D-09 断食提醒互补）；
/// - 节奏 = 进食窗口内每本地整点一条（48h 视界，与断食通知同视界）；
/// - 达标即停发：按「归属日」分组判定——今日已摄入量达标则剔除今日全部
///   触发点，次日重新计数不受今日影响；
/// - 触发点数量随用户实际进食窗口长短自然变化（16:8 每天约 8 个整点、
///   14:10 约 10 个），不写死断食时长；喝水入账后重排，建议量随剩余量
///   收敛，确保到进食窗口结束前达成目标。

/// 计划中的一条喝水提醒。
final class PlannedWaterReminder {
  const PlannedWaterReminder({
    required this.id,
    required this.triggerAtUtcSec,
    required this.suggestedMl,
    required this.remainingMl,
    required this.attributionDate,
  });

  /// 通知 id（int32，触发分钟 × 10 + 3；3 = 喝水序号，避开断食 0/1/2，
  /// 同分钟不冲突）。
  final int id;

  /// 触发时刻（UTC epoch 秒，本地整点）。
  final int triggerAtUtcSec;

  /// 建议饮水量（毫升）：当日剩余量 ÷ 当日剩余触发点数，向上取整。
  final int suggestedMl;

  /// 触发时归属日的剩余待完成量（毫升，计划生成时点口径）。
  final int remainingMl;

  /// 归属日（触发时刻的本地自然日，达标判定分组键）。
  final LocalDate attributionDate;

  @override
  bool operator ==(Object other) =>
      other is PlannedWaterReminder &&
      other.id == id &&
      other.triggerAtUtcSec == triggerAtUtcSec &&
      other.suggestedMl == suggestedMl &&
      other.remainingMl == remainingMl &&
      other.attributionDate == attributionDate;

  @override
  int get hashCode => Object.hash(
    id,
    triggerAtUtcSec,
    suggestedMl,
    remainingMl,
    attributionDate,
  );

  @override
  String toString() =>
      'PlannedWaterReminder($triggerAtUtcSec, ${suggestedMl}ml)';
}

/// 喝水提醒通知 id：触发分钟 × 10 + 3（kind 序号 3；断食三类占 0/1/2，
/// 见 `fastingNotificationId`）。
int waterReminderNotificationId(int triggerAtUtcSec) =>
    (triggerAtUtcSec ~/ 60) * 10 + 3;

/// 生成未来 [horizonSec] 内的喝水提醒计划。
///
/// - [plan]：生效断食方案（进食窗口来源；调用方在 NO_PLAN 时不应调用本
///   函数——与断食调度器 plan==null 清空语义一致）；
/// - [alreadyMl]：**今日**（[nowUtcSec] 归属日）已摄入毫升数；次日按 0 计；
/// - [goalMl]：每日目标（与 `WaterLogRepository.dailyGoalMl` 同口径）；
/// - [intervalSec]：提醒间隔（默认 1h，对齐本地整点）。
///
/// 返回按触发时刻升序的列表；仅含 `(now, now + horizon]` 内、且落在
/// 进食窗口 `[eatStart, eatEnd)` 的本地整点（跨午夜窗口由 `anchorsFor`
/// 防御口径覆盖：当日尾段 + 次日晨段各自归属所在自然日）。
List<PlannedWaterReminder> buildWaterReminderPlan({
  required FastingPlan plan,
  required int alreadyMl,
  required int nowUtcSec,
  required tz.Location location,
  int goalMl = 2000,
  int intervalSec = 3600,
  int horizonSec = 48 * 3600,
}) {
  final today = localDateOf(nowUtcSec, location);

  // 1) 收集视界内窗口内整点，按归属日分组。
  final byDate = <LocalDate, List<int>>{};
  for (var offset = -1; offset <= 2; offset++) {
    final date = today.addDays(offset);
    final anchors = anchorsFor(plan, date, location);
    final midnight = localMidnightUtc(date, location);
    // 网格扩到 ±24h：跨午夜窗口（如 20:00→04:00）的次日晨段落在 D 的
    // anchorsFor 区间内、却不在 D 自身的 0..23 整点网格上，必须借相邻日
    // 网格生成；归属日统一用 localDateOf(t)（半开区间互不重叠，去重保险）。
    for (var k = -24; k < 48; k++) {
      final t = midnight + k * intervalSec;
      if (t <= nowUtcSec || t > nowUtcSec + horizonSec) continue;
      if (t < anchors.eatStartUtc || t >= anchors.eatEndUtc) continue;
      final bucket = byDate.putIfAbsent(localDateOf(t, location), () => []);
      if (!bucket.contains(t)) bucket.add(t);
    }
  }

  // 2) 逐日：达标日剔除；建议量 = 当前剩余量 ÷ 当日剩余触发点数，
  //    向上取整后对齐 50ml 档（贴合快捷入账 200/300/500 粒度，不足 50 取
  //    50）。逐触发点递减剩余量——用户若按建议喝完，后续提醒的建议量
  //    自动收敛；实际喝多喝少由下一次「喝水入账重排」重新校准。
  final items = <PlannedWaterReminder>[];
  for (final entry in byDate.entries) {
    final already = entry.key == today ? alreadyMl : 0;
    var remaining = goalMl - already;
    if (remaining <= 0) continue; // 达标：当日不再提醒。
    final triggers = entry.value..sort();
    for (var i = 0; i < triggers.length; i++) {
      final slotsLeft = triggers.length - i;
      final raw = (remaining + slotsLeft - 1) ~/ slotsLeft;
      final suggested = raw < 50 ? 50 : ((raw + 49) ~/ 50) * 50;
      items.add(
        PlannedWaterReminder(
          id: waterReminderNotificationId(triggers[i]),
          triggerAtUtcSec: triggers[i],
          suggestedMl: suggested,
          remainingMl: remaining,
          attributionDate: entry.key,
        ),
      );
      remaining -= suggested;
    }
  }
  items.sort((a, b) => a.triggerAtUtcSec.compareTo(b.triggerAtUtcSec));
  return items;
}

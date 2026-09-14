import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:timezone/timezone.dart' as tz;

/// 断食计时状态机（《规格-M2》§2–§5 的纯函数实现）。
///
/// 铁律（§2.3）：任何迁移都是「读 UTC 锚点 → 纯函数计算 → 写记录 +
/// 重排通知 + 刷小组件」，本文件只负责纯函数部分，无副作用、无时钟依赖
/// （now 一律以参数传入）、无全局状态。

/// 破窗容差默认值（D-08：15 分钟，走服务端配置热调 `fast_tolerance_sec`）。
const int kDefaultToleranceSec = 900;

/// 延长步进（D-10：30 分钟）。
const int kExtendStepMinutes = 30;

/// 单周期累计延长上限（D-10：4 小时；〔假设〕按「单 FastCycle 累计」理解）。
const int kExtendMaxMinutes = 240;

/// 状态落点快照（§4.2 `resolve_state` 输出）。
final class FastingSnapshot {
  const FastingSnapshot({
    required this.state,
    required this.nowUtc,
    this.cycle,
    this.targetUtc,
    this.attributionPreview,
  });

  /// 当前应用级状态。
  final FastingState state;

  /// 计算所用 now（UTC epoch 秒）。
  final int nowUtc;

  /// 当前进行中的 FastCycle（仅 fasting / fastingExtended 非空）。
  final FastCycle? cycle;

  /// 倒计时目标锚点：fasting → 计划进食开始；eating → 进食窗口结束。
  final int? targetUtc;

  /// 倒计时秒数，任何情况下不为负（§3.4）。
  int get countdownSec {
    final target = targetUtc;
    if (target == null) return 0;
    final remaining = target - nowUtc;
    return remaining > 0 ? remaining : 0;
  }

  /// 预计算归属日（§3.3：进行中允许随时区变化实时更新，直至冻结）。
  /// fasting → 计划进食开始锚点的本地日；eating → 下一进食窗口的本地日。
  final LocalDate? attributionPreview;
}

/// 状态落点重算（§4.2 伪代码：时区变更/校时/恢复共用）。
///
/// 原则：以「当前时刻之后最近的窗口边界」重建所处区间。
FastingSnapshot resolveState(
  int nowUtc,
  FastingPlan plan,
  tz.Location location,
) {
  final today = localDateOf(nowUtc, location);
  // 覆盖 [昨天, 后天] 的窗口锚点，正常 now 必落在覆盖范围内；
  // 越界 now（时钟大幅拨快/回拨）由循环后的兜底分支防御性落点。
  final anchors = <({int eatStartUtc, int eatEndUtc})>[
    for (var i = -1; i <= 2; i++) anchorsFor(plan, today.addDays(i), location),
  ];
  // 上界取 anchors.length - 1：循环体内恒读 anchors[i + 1]，
  // 放开到 anchors.length 会在末位下标越界抛 RangeError 打挂首页。
  for (var i = 0; i < anchors.length - 1; i++) {
    final a = anchors[i];
    if (a.eatStartUtc <= nowUtc && nowUtc < a.eatEndUtc) {
      // EATING：倒计时 = 距进食窗口结束（T10 反向）
      final next = anchors[i + 1];
      return FastingSnapshot(
        state: FastingState.eating,
        nowUtc: nowUtc,
        targetUtc: a.eatEndUtc,
        attributionPreview: localDateOf(next.eatStartUtc, location),
      );
    }
    final next = anchors[i + 1];
    if (a.eatEndUtc <= nowUtc && nowUtc < next.eatStartUtc) {
      // FASTING：FastCycle(n) = [eatEnd(n-1), eatStart(n))（§3.2）
      final cycle = FastCycle(
        startUtc: a.eatEndUtc,
        plannedEndUtc: next.eatStartUtc,
        eatWindowEndUtc: next.eatEndUtc,
      );
      return FastingSnapshot(
        state: cycle.state,
        nowUtc: nowUtc,
        cycle: cycle,
        targetUtc: next.eatStartUtc,
        attributionPreview: localDateOf(next.eatStartUtc, location),
      );
    }
  }
  // 兜底：now ≥ 最后一个进食窗口开始锚点（时钟拨快越界，B10）——
  // 落到最近区间而不是抛异常：进食窗内判 EATING，否则以最后进食结束
  // 锚点为起点、按需补算的下一进食锚点为终点构造断食周期。
  final last = anchors.last;
  if (last.eatStartUtc <= nowUtc) {
    final next = anchorsFor(plan, today.addDays(3), location);
    if (nowUtc < last.eatEndUtc) {
      return FastingSnapshot(
        state: FastingState.eating,
        nowUtc: nowUtc,
        targetUtc: last.eatEndUtc,
        attributionPreview: localDateOf(next.eatStartUtc, location),
      );
    }
    final cycle = FastCycle(
      startUtc: last.eatEndUtc,
      plannedEndUtc: next.eatStartUtc,
      eatWindowEndUtc: next.eatEndUtc,
    );
    return FastingSnapshot(
      state: cycle.state,
      nowUtc: nowUtc,
      cycle: cycle,
      targetUtc: next.eatStartUtc,
      attributionPreview: localDateOf(next.eatStartUtc, location),
    );
  }
  // 兜底：now 早于覆盖范围（时钟回拨越界，B9）——落到首个进食窗口前的
  // 断食区间（起点为按需补算的前一进食结束锚点）；§4.4 回拨不惩罚，
  // 倒计时按锚点自然变长。
  final first = anchors.first;
  final prev = anchorsFor(plan, today.addDays(-2), location);
  final cycle = FastCycle(
    startUtc: prev.eatEndUtc,
    plannedEndUtc: first.eatStartUtc,
    eatWindowEndUtc: first.eatEndUtc,
  );
  return FastingSnapshot(
    state: cycle.state,
    nowUtc: nowUtc,
    cycle: cycle,
    targetUtc: first.eatStartUtc,
    attributionPreview: localDateOf(first.eatStartUtc, location),
  );
}

/// 关闭周期（§3.3 `close_cycle` 伪代码的可运行实现，D-07/D-08）。
///
/// - 归属日 = [endUtc] 在 [tzAtEnd] 下渲染的自然日，写入后冻结不改写；
/// - 达标判定容差 [toleranceSec] 走服务端配置（默认 900s，D-08）。
FastingRecord closeCycle(
  FastCycle cycle,
  int endUtc,
  tz.Location tzAtEnd,
  CloseReason reason, {
  int toleranceSec = kDefaultToleranceSec,
}) {
  final attributionDate = localDateOf(endUtc, tzAtEnd).toIsoString();
  final actual = endUtc - cycle.startUtc;
  final planned = cycle.plannedEndUtc - cycle.startUtc;
  final plannedOriginal = planned - cycle.extendedMinutes * 60;

  final CycleResult result;
  final bool qualified;
  switch (reason) {
    case CloseReason.windowStartDue:
      result = cycle.extendedMinutes == 0
          ? CycleResult.completedOnTime
          : CycleResult.completedExtended;
      qualified = true;
    case CloseReason.manualEnd:
      final earlyBy = cycle.plannedEndUtc - endUtc; // >0 表示提前
      if (cycle.extendedMinutes > 0 && actual >= plannedOriginal) {
        // D-08 延长条款：延长后最终断食时长 ≥ 计划时长 → 仍记达标
        result = CycleResult.completedExtended;
        qualified = true;
      } else if (earlyBy <= toleranceSec) {
        // D-08 容差条款（<= 含边界，B4）
        result = CycleResult.completedEarlyPass;
        qualified = true;
      } else {
        result = CycleResult.brokenEarly;
        qualified = false;
      }
  }
  return FastingRecord(
    date: attributionDate,
    startUtc: cycle.startUtc,
    endUtc: endUtc,
    actualSec: actual,
    plannedSec: planned,
    extendedMinutes: cycle.extendedMinutes,
    result: result,
    qualified: qualified,
  );
}

/// 延长（T5/T6/T7，D-10/§4.3）。
///
/// 步进 [stepMinutes]，单周期累计上限 [maxMinutes]；只后移进食窗口开始
/// 锚点与当日进食结束锚点，进食窗口总时长不压缩；不跨周期继承。
/// 已达上限时返回 null（T7：按钮置 disabled）。
FastCycle? extendCycle(
  FastCycle cycle, {
  int stepMinutes = kExtendStepMinutes,
  int maxMinutes = kExtendMaxMinutes,
}) {
  if (cycle.extendedMinutes >= maxMinutes) return null;
  final step = (cycle.extendedMinutes + stepMinutes > maxMinutes)
      ? maxMinutes - cycle.extendedMinutes
      : stepMinutes;
  return cycle.copyWith(
    plannedEndUtc: cycle.plannedEndUtc + step * 60,
    eatWindowEndUtc: cycle.eatWindowEndUtc + step * 60,
    extendedMinutes: cycle.extendedMinutes + step,
  );
}

/// D-08 预判：若 [nowUtc] 手动结束本周期是否达标（与 closeCycle 的
/// manualEnd 判定同口径——延长条款优先于容差条款），供确认弹窗
/// 在结束前置警示「本次将记为不达标」。
bool wouldManualEndQualify(
  FastCycle cycle,
  int nowUtc, {
  int toleranceSec = kDefaultToleranceSec,
}) {
  final actual = nowUtc - cycle.startUtc;
  final planned = cycle.plannedEndUtc - cycle.startUtc;
  final plannedOriginal = planned - cycle.extendedMinutes * 60;
  if (cycle.extendedMinutes > 0 && actual >= plannedOriginal) return true;
  final earlyBy = cycle.plannedEndUtc - nowUtc; // >0 表示提前
  return earlyBy <= toleranceSec;
}

/// 手动「结束断食」（T3/T4/T9，仅 FASTING / FASTING_EXTENDED 下可达，
/// EATING 下防御性丢弃见 T11，由调用侧保证）。
///
/// 返回关闭记录；下一状态恒为 EATING（进食窗口结束锚点不后移〔假设〕）。
FastingRecord manualEndFast(
  FastCycle cycle,
  int nowUtc,
  tz.Location location, {
  int toleranceSec = kDefaultToleranceSec,
}) {
  return closeCycle(
    cycle,
    nowUtc,
    location,
    CloseReason.manualEnd,
    toleranceSec: toleranceSec,
  );
}

/// 进食窗口到点自然关闭（T2/T8：now ≥ plannedEnd 时按锚点关闭）。
FastingRecord completeCycleOnTime(FastCycle cycle, tz.Location location) {
  return closeCycle(
    cycle,
    cycle.plannedEndUtc,
    location,
    CloseReason.windowStartDue,
  );
}

/// 待生效方案（T12，D-06：次日 0:00 本地生效）。
final class PendingPlan {
  const PendingPlan({
    required this.plan,
    required this.effectiveDate,
    required this.effectiveUtc,
  });

  /// 新方案。
  final FastingPlan plan;

  /// 生效日（本地自然日）。
  final LocalDate effectiveDate;

  /// 生效时刻（本地 0:00 换算 UTC epoch 秒）。
  final int effectiveUtc;
}

/// 方案更换登记（T12，D-06）。
///
/// 确认弹窗须明示「新方案将于生效日 0:00 生效」；
/// 当日锚点不动，已记录数据保留不回算。
PendingPlan schedulePlanChange(
  FastingPlan newPlan,
  int nowUtc,
  tz.Location location,
) {
  final tomorrow = localDateOf(nowUtc, location).addDays(1);
  return PendingPlan(
    plan: newPlan,
    effectiveDate: tomorrow,
    effectiveUtc: localMidnightUtc(tomorrow, location),
  );
}

/// 新方案生效判定（T13）：[nowUtc] 到达本地 0:00 后返回新方案，否则 null。
///
/// 转正后从今日起的周期按新窗口计算（§4.2 重算落点）；
/// 杀进程场景由 `APP_FOREGROUND` 对账时调用本函数兜底转正（§4.1）。
FastingPlan? activatePendingPlan(PendingPlan pending, int nowUtc) {
  return nowUtc >= pending.effectiveUtc ? pending.plan : null;
}

/// 前台恢复/校时对账结果（T15/T16）。
final class ReconcileResult {
  const ReconcileResult({
    required this.snapshot,
    required this.closedRecords,
    required this.clockRollbackDetected,
  });

  /// 按锚点重算后的当前状态。
  final FastingSnapshot snapshot;

  /// 离线期间跨过窗口边界而补关闭的周期（B10/B12：按 T2/T8 规则）。
  final List<FastingRecord> closedRecords;

  /// 回拨侦测（§4.4：lastSeenUtc > now → 回拨；不惩罚、不判破窗、
  /// 已冻结记录不回滚，倒计时按锚点自然变长）。
  final bool clockRollbackDetected;
}

/// 恢复对账（T16 `APP_FOREGROUND` / T15 `CLOCK_CHANGED` 共用）。
///
/// - [openCycles]：本地持久化的进行中周期（可能多个，B12 多天未打开）；
/// - 离线期间跨过窗口边界的周期按 `COMPLETED_*` 补关闭——周期关闭不依赖
///   前台（B12〔假设〕：MVP 不存在真正的漏打卡，`MISSED` 仅覆盖无方案日）；
/// - [lastSeenUtc] 用于回拨侦测（B9）；拨快跨过边界按正常迁移补关闭（B10）。
ReconcileResult reconcile({
  required List<FastCycle> openCycles,
  required int nowUtc,
  required FastingPlan plan,
  required tz.Location location,
  int? lastSeenUtc,
}) {
  final rollback = lastSeenUtc != null && lastSeenUtc > nowUtc;
  final closed = <FastingRecord>[];
  for (final cycle in openCycles) {
    if (cycle.plannedEndUtc <= nowUtc) {
      closed.add(completeCycleOnTime(cycle, location));
    }
  }
  return ReconcileResult(
    snapshot: resolveState(nowUtc, plan, location),
    closedRecords: closed,
    clockRollbackDetected: rollback,
  );
}

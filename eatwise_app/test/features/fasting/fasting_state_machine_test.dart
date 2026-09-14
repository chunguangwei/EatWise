import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'tz_test_helper.dart';

/// 《规格-M2 断食计时状态机与边界用例》§6 边界用例表 B1–B15 全量覆盖。
/// 时间线约定：BJT = Asia/Shanghai（UTC+8）；默认方案 16:8（12:00–20:00），
/// 容差 15min（D-08）。
void main() {
  late tz.Location bjt;
  late tz.Location ny;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
    ny = tz.getLocation('America/New_York');
  });

  /// 本地墙钟 → UTC epoch 秒（测试显式构造时区场景，§3.4）。
  int wall(int y, int m, int d, int h, int min, tz.Location loc) =>
      tz.TZDateTime(loc, y, m, d, h, min).millisecondsSinceEpoch ~/ 1000;

  const plan = FastingPlan.plan16x8;

  test('B1 跨午夜窗口（常规日）：到点关闭 COMPLETED_ON_TIME，归属日 = d+1（D-07/D-08/T2）', () {
    // d = 2026-07-27（BJT）
    final fastStart = wall(2026, 7, 27, 20, 0, bjt);
    final eatStart = wall(2026, 7, 28, 12, 0, bjt);

    // d 日 20:00 → FASTING，倒计时 16h，预计算归属日 d+1
    final s1 = resolveState(fastStart, plan, bjt);
    expect(s1.state, FastingState.fasting);
    expect(s1.countdownSec, 16 * 3600);
    expect(s1.attributionPreview, const LocalDate(2026, 7, 28));

    // 计时环在 d 日 23:59 → d+1 日 00:00 无跳变（倒计时连续递减）
    final before = resolveState(wall(2026, 7, 27, 23, 59, bjt), plan, bjt);
    final after = resolveState(wall(2026, 7, 28, 0, 1, bjt), plan, bjt);
    expect(before.state, FastingState.fasting);
    expect(after.state, FastingState.fasting);
    expect(before.countdownSec - after.countdownSec, 2 * 60);

    // d+1 日 12:00 → EATING；周期关闭 COMPLETED_ON_TIME，归属日 d+1，达标
    final s2 = resolveState(eatStart, plan, bjt);
    expect(s2.state, FastingState.eating);
    final record = completeCycleOnTime(s1.cycle!, bjt);
    expect(record.result, CycleResult.completedOnTime);
    expect(record.date, '2026-07-28');
    expect(record.qualified, isTrue);
    expect(record.actualSec, 16 * 3600);
  });

  test('B2 提前结束 ≤15min（14min）→ COMPLETED_EARLY_PASS 达标（D-08/T3）', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final record = manualEndFast(cycle, wall(2026, 7, 28, 11, 46, bjt), bjt);
    expect(record.result, CycleResult.completedEarlyPass);
    expect(record.qualified, isTrue);
    expect(record.date, '2026-07-28');
    expect(record.actualSec, 15 * 3600 + 46 * 60); // 20:00 → 11:46
  });

  test('B3 提前结束 >15min（16min）→ BROKEN_EARLY 不达标（D-08/T4）', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final record = manualEndFast(cycle, wall(2026, 7, 28, 11, 44, bjt), bjt);
    expect(record.result, CycleResult.brokenEarly);
    expect(record.qualified, isFalse);
    expect(record.date, '2026-07-28');
    expect(record.actualSec, 15 * 3600 + 44 * 60);
  });

  test('B4 提前恰好 15min → 达标（容差判定为 <=，含边界，D-08）；'
      '15min01s → 不达标', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final atBoundary = manualEndFast(
      cycle,
      wall(2026, 7, 28, 11, 45, bjt), // 提前 900s
      bjt,
    );
    expect(atBoundary.result, CycleResult.completedEarlyPass);
    expect(atBoundary.qualified, isTrue);

    final overBoundary = manualEndFast(
      cycle,
      wall(2026, 7, 28, 11, 44, bjt) + 59, // 提前 901s
      bjt,
    );
    expect(overBoundary.result, CycleResult.brokenEarly);
    expect(overBoundary.qualified, isFalse);
  });

  test('B4+ 容差走配置可热调（D-08）：tolerance=0 时提前 14min 也破窗', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final record = manualEndFast(
      cycle,
      wall(2026, 7, 28, 11, 46, bjt),
      bjt,
      toleranceSec: 0,
    );
    expect(record.result, CycleResult.brokenEarly);
  });

  test('B5 延长步进与上限：×8 累计 4h 后按钮 disabled；'
      '16:00 到点 COMPLETED_EXTENDED；进食窗口 8h 不压缩（D-10/T5–T8）', () {
    var cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final originalEatEnd = cycle.eatWindowEndUtc;

    // 延长 ×8：每次 +30min，extendMinutes 累加
    for (var i = 1; i <= 8; i++) {
      final next = extendCycle(cycle);
      expect(next, isNotNull);
      cycle = next!;
      expect(cycle.extendedMinutes, i * 30);
      expect(cycle.state, FastingState.fastingExtended);
    }
    // 进食开始 12:00 → 16:00；当日进食窗口 16:00–24:00，时长 8h 不压缩
    expect(cycle.plannedEndUtc, wall(2026, 7, 28, 16, 0, bjt));
    expect(cycle.eatWindowEndUtc, originalEatEnd + 4 * 3600);
    expect(cycle.eatWindowEndUtc - cycle.plannedEndUtc, 8 * 3600);

    // 第 9 次：已达上限 → null（T7 按钮置 disabled）
    expect(extendCycle(cycle), isNull);

    // 16:00 到点 → COMPLETED_EXTENDED，归属日 d+1，达标
    final record = completeCycleOnTime(cycle, bjt);
    expect(record.result, CycleResult.completedExtended);
    expect(record.qualified, isTrue);
    expect(record.date, '2026-07-28');
    expect(record.actualSec, 20 * 3600);
  });

  test('B6 延长后提前结束但 ≥ 原计划 → COMPLETED_EXTENDED（D-08 延长条款/T9）', () {
    var cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    cycle = extendCycle(cycle)!; // +30min
    cycle = extendCycle(cycle)!; // +30min，新目标 13:00
    expect(cycle.plannedEndUtc, wall(2026, 7, 28, 13, 0, bjt));

    // 12:30 手动结束：实际 16.5h ≥ 原计划 16h → 达标
    final pass = manualEndFast(cycle, wall(2026, 7, 28, 12, 30, bjt), bjt);
    expect(pass.result, CycleResult.completedExtended);
    expect(pass.qualified, isTrue);

    // 对照：11:50 结束，实际 15h50m < 原计划 16h，且提前 70min > 容差 → 破窗
    final broken = manualEndFast(cycle, wall(2026, 7, 28, 11, 50, bjt), bjt);
    expect(broken.result, CycleResult.brokenEarly);
    expect(broken.qualified, isFalse);
  });

  test('B7 方案更换次日生效（D-06/T12/T13）：当日按旧方案，'
      'd+1 00:00 本地转正，d+1 10:00 按新窗口进食', () {
    final changeAt = wall(2026, 7, 27, 15, 0, bjt);
    final pending = schedulePlanChange(FastingPlan.plan14x10, changeAt, bjt);

    // 生效时刻 = 本地次日 0:00
    expect(pending.effectiveDate, const LocalDate(2026, 7, 28));
    expect(pending.effectiveUtc, wall(2026, 7, 28, 0, 0, bjt));

    // 当日仍按旧方案：15:00 处于 EATING（旧窗口 12:00–20:00），未转正
    expect(activatePendingPlan(pending, changeAt), isNull);
    expect(resolveState(changeAt, plan, bjt).state, FastingState.eating);

    // d+1 00:00（本地）PLAN_ACTIVATE 转正
    final activated = activatePendingPlan(pending, pending.effectiveUtc);
    expect(activated, FastingPlan.plan14x10);

    // d+1 10:00：新方案已到进食窗口，旧方案仍在断食；d 日记录不回算
    final d1Morning = wall(2026, 7, 28, 10, 0, bjt);
    expect(resolveState(d1Morning, activated!, bjt).state, FastingState.eating);
    expect(resolveState(d1Morning, plan, bjt).state, FastingState.fasting);
  });

  group('resolveState 越界防御（时钟大幅拨快/回拨，B9/B10 回归）', () {
    // 回归：循环末位无条件读 anchors[i + 1]，越界 now 会 RangeError 打挂
    // 首页；修复后越界 now 防御性落到最近区间，正常 now 落点不变。
    test('拨快 48h：落点与直接锚点推导一致，不抛异常', () {
      final base = wall(2026, 7, 28, 12, 0, bjt); // 本地 12:00，进食窗内
      final later = base + 48 * 3600; // 2026-07-30 12:00 本地
      final s = resolveState(later, plan, bjt);
      expect(s.state, FastingState.eating);
      expect(s.targetUtc, wall(2026, 7, 30, 20, 0, bjt));
      expect(s.countdownSec, 8 * 3600);
      expect(s.attributionPreview, const LocalDate(2026, 7, 31));
    });

    test('拨快一周：断食段落点正确，周期锚点与墙钟一致', () {
      final base = wall(2026, 7, 28, 8, 0, bjt); // 本地 08:00，断食中
      final later = base + 7 * 24 * 3600; // 2026-08-04 08:00 本地
      final s = resolveState(later, plan, bjt);
      expect(s.state, FastingState.fasting);
      expect(s.cycle!.startUtc, wall(2026, 8, 3, 20, 0, bjt));
      expect(s.cycle!.plannedEndUtc, wall(2026, 8, 4, 12, 0, bjt));
      expect(s.countdownSec, 4 * 3600);
    });

    test('回拨一周：仍按回拨后墙钟正常落点，不抛异常', () {
      final base = wall(2026, 7, 28, 12, 0, bjt);
      final earlier = base - 7 * 24 * 3600; // 2026-07-21 12:00 本地
      final s = resolveState(earlier, plan, bjt);
      expect(s.state, FastingState.eating);
      expect(s.countdownSec, 8 * 3600);
    });
  });

  test('B8 飞行跨时区（北京→纽约，D-07/T14）：UTC 锚点不变，'
      '预计算归属日随时区变化，关闭时冻结', () {
    // 用冬季（EST，UTC-5）场景：锚点 04:00 UTC 在 NY 渲染为前一日 23:00，
    // 归属日由 BJT d+1 变为 NY d（B8 预期语义）。
    // 注：B8 原文取 UTC-4（夏令时）时 NY 渲染恰为 00:00，归属日与 BJT 同日；
    // 其「纽约 d 日」表述按 UTC-5（或锚点非整 04:00）理解。
    final d = const LocalDate(2026, 1, 15);
    final anchors = anchorsFor(plan, d.addDays(1), bjt);
    final fastStart = anchorsFor(plan, d, bjt).eatEndUtc; // d 20:00 BJT
    final cycle = FastCycle(
      startUtc: fastStart,
      plannedEndUtc: anchors.eatStartUtc, // d+1 12:00 BJT = d+1 04:00 UTC
      eatWindowEndUtc: anchors.eatEndUtc,
    );

    // UTC 锚点不变：进食开始 = d+1 04:00 UTC
    expect(cycle.plannedEndUtc, wall(2026, 1, 16, 12, 0, bjt));

    // BJT 下预计算归属日 = d+1；纽约（EST）下同锚点 = d 日 23:00 → 归属日变 d
    expect(localDateOf(cycle.plannedEndUtc, bjt), d.addDays(1));
    expect(localDateOf(cycle.plannedEndUtc, ny), d);
    final nyLocal = toLocal(cycle.plannedEndUtc, ny);
    expect(nyLocal.hour, 23); // 纽约墙钟 23:00（锚点未变，渲染随新时区）

    // 落地纽约后按新时区重算落点：仍是 FASTING，状态枚举不翻转
    final duringFlight = cycle.plannedEndUtc - 3600;
    expect(resolveState(duringFlight, plan, ny).state, FastingState.fasting);

    // 周期关闭时冻结归属日 = 纽约 d 日，达标；冻结后不再改写
    final record = completeCycleOnTime(cycle, ny);
    expect(record.date, '2026-01-15');
    expect(record.result, CycleResult.completedOnTime);
    expect(record.qualified, isTrue);
  });

  test('B9 手动回拨系统时间（§4.4/T15）：检测回拨，倒计时自然变长，'
      '不判破窗、不改已冻结记录', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final realNow = wall(2026, 7, 28, 10, 0, bjt); // 真实 10:00，剩 2h
    final rolledBack = wall(2026, 7, 28, 7, 0, bjt); // 回拨到 07:00

    final result = reconcile(
      openCycles: <FastCycle>[cycle],
      nowUtc: rolledBack,
      plan: plan,
      location: bjt,
      lastSeenUtc: realNow,
    );
    expect(result.clockRollbackDetected, isTrue);
    expect(result.closedRecords, isEmpty); // 不判破窗、不补关闭
    expect(result.snapshot.state, FastingState.fasting);
    // 锚点不变 → 倒计时由「剩 2h」如实变为「剩 5h」
    expect(result.snapshot.countdownSec, 5 * 3600);
  });

  test('B10 手动拨快系统时间（§4.4/T15）：跨过进食开始 → '
      '按 COMPLETED_ON_TIME 补关闭并进 EATING（B10）', () {
    final cycle = resolveState(wall(2026, 7, 27, 21, 0, bjt), plan, bjt).cycle!;
    final jumped = wall(2026, 7, 28, 13, 0, bjt); // 09:00 拨快 4h 至 13:00

    final result = reconcile(
      openCycles: <FastCycle>[cycle],
      nowUtc: jumped,
      plan: plan,
      location: bjt,
      lastSeenUtc: wall(2026, 7, 28, 9, 0, bjt),
    );
    expect(result.clockRollbackDetected, isFalse);
    expect(result.closedRecords, hasLength(1));
    expect(result.closedRecords.single.result, CycleResult.completedOnTime);
    expect(result.closedRecords.single.date, '2026-07-28');
    expect(result.closedRecords.single.qualified, isTrue);
    expect(result.snapshot.state, FastingState.eating);
  });

  test('B11 夏令时春天拨快 1h（America/New_York）：当日断食实际 15h，'
      '按计划锚点到点仍达标（B11）', () {
    // 2026-03-08 02:00 → 03:00（EST → EDT）
    final fastStart = wall(2026, 3, 7, 20, 0, ny); // EST = UTC 03-08 01:00
    final eatStart = wall(2026, 3, 8, 12, 0, ny); // EDT = UTC 03-08 16:00
    final cycle = FastCycle(
      startUtc: fastStart,
      plannedEndUtc: eatStart,
      eatWindowEndUtc: wall(2026, 3, 8, 20, 0, ny),
    );
    expect(eatStart - fastStart, 15 * 3600); // 少 1h

    final record = completeCycleOnTime(cycle, ny);
    expect(record.result, CycleResult.completedOnTime);
    expect(record.qualified, isTrue);
    expect(record.date, '2026-03-08');
    expect(record.actualSec, 15 * 3600);

    // 切换日凌晨按新时区重算落点正常
    expect(
      resolveState(wall(2026, 3, 8, 11, 0, ny), plan, ny).countdownSec,
      3600,
    );
  });

  test('B11b 夏令时秋天回拨 1h：当日断食实际 17h，归属日不变，达标（B11b）', () {
    // 2026-11-01 02:00 → 01:00（EDT → EST）
    final fastStart = wall(2026, 10, 31, 20, 0, ny); // EDT = UTC 11-01 00:00
    final eatStart = wall(2026, 11, 1, 12, 0, ny); // EST = UTC 11-01 17:00
    final cycle = FastCycle(
      startUtc: fastStart,
      plannedEndUtc: eatStart,
      eatWindowEndUtc: wall(2026, 11, 1, 20, 0, ny),
    );
    expect(eatStart - fastStart, 17 * 3600); // 多 1h

    final record = completeCycleOnTime(cycle, ny);
    expect(record.result, CycleResult.completedOnTime);
    expect(record.qualified, isTrue);
    expect(record.date, '2026-11-01');
    expect(record.actualSec, 17 * 3600);
  });

  test('B12 跨天未打开 App（T16）：启动对账按锚点补关闭 d+1/d+2 周期，'
      '归属日各自正确、均达标（B12）', () {
    // d 日 20:00 断食开始后 d+1、d+2 两日未打开，d+3 日 13:00 打开
    // （d+2 周期于 d+3 12:00 到点，对账时一并补关闭）
    final cycles = <FastCycle>[
      for (var i = 0; i < 3; i++)
        FastCycle(
          startUtc: wall(2026, 7, 27 + i, 20, 0, bjt),
          plannedEndUtc: wall(2026, 7, 28 + i, 12, 0, bjt),
          eatWindowEndUtc: wall(2026, 7, 28 + i, 20, 0, bjt),
        ),
    ];
    final result = reconcile(
      openCycles: cycles,
      nowUtc: wall(2026, 7, 30, 13, 0, bjt),
      plan: plan,
      location: bjt,
    );
    expect(result.closedRecords, hasLength(3));
    expect(result.closedRecords.map((r) => r.date), <String>[
      '2026-07-28',
      '2026-07-29',
      '2026-07-30',
    ]);
    expect(
      result.closedRecords.every(
        (r) => r.result == CycleResult.completedOnTime && r.qualified,
      ),
      isTrue,
    );
    // 当前处于 d+3 进食窗口中（13:00 已过 12:00 进食开始锚点）
    expect(result.snapshot.state, FastingState.eating);
  });

  test('B13 杀进程后重开（T16）：按锚点重算，倒计时连续、误差 0（B13）', () {
    final before = resolveState(wall(2026, 7, 27, 23, 0, bjt), plan, bjt);
    // 杀进程 30min 后重开：APP_FOREGROUND 恢复
    final after = reconcile(
      openCycles: <FastCycle>[before.cycle!],
      nowUtc: wall(2026, 7, 27, 23, 30, bjt),
      plan: plan,
      location: bjt,
    );
    expect(after.closedRecords, isEmpty);
    expect(after.snapshot.state, FastingState.fasting);
    expect(after.snapshot.targetUtc, before.targetUtc); // 同一锚点
    expect(before.countdownSec - after.snapshot.countdownSec, 30 * 60);
  });

  test('B14 设备重启（T16）：2h 后开机，锚点不变、倒计时精确递减（B14）', () {
    final before = resolveState(wall(2026, 7, 27, 22, 0, bjt), plan, bjt);
    // 重启 2h 后首开（Android 端 BOOT_COMPLETED 重排通知为原生侧职责，
    // Spike 验证锚点模型保证重开即正确）
    final after = reconcile(
      openCycles: <FastCycle>[before.cycle!],
      nowUtc: wall(2026, 7, 28, 0, 0, bjt),
      plan: plan,
      location: bjt,
    );
    expect(after.snapshot.targetUtc, before.targetUtc);
    expect(before.countdownSec - after.snapshot.countdownSec, 2 * 3600);
    expect(after.snapshot.attributionPreview, const LocalDate(2026, 7, 28));
  });

  test('B15 跨午夜 + 延长联合：23:30 延长 30min，进食开始 12:00→12:30，'
      '归属日不变，到点 COMPLETED_EXTENDED（B15/D-10）', () {
    var cycle = resolveState(wall(2026, 7, 27, 23, 30, bjt), plan, bjt).cycle!;
    expect(cycle.startUtc, wall(2026, 7, 27, 20, 0, bjt));

    cycle = extendCycle(cycle)!;
    expect(cycle.extendedMinutes, 30);
    expect(cycle.plannedEndUtc, wall(2026, 7, 28, 12, 30, bjt));
    // 归属日不变（d+1）
    expect(localDateOf(cycle.plannedEndUtc, bjt), const LocalDate(2026, 7, 28));

    final record = completeCycleOnTime(cycle, bjt);
    expect(record.result, CycleResult.completedExtended);
    expect(record.qualified, isTrue);
    expect(record.date, '2026-07-28');
    expect(record.actualSec, 16 * 3600 + 30 * 60);
  });

  test('T11 防御：EATING 状态下无进行中周期，手动事件不可达', () {
    final eating = resolveState(wall(2026, 7, 27, 15, 0, bjt), plan, bjt);
    expect(eating.state, FastingState.eating);
    expect(eating.cycle, isNull); // 调用侧依此为事件不可达的判据
  });
}

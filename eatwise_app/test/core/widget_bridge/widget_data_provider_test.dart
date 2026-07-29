import 'package:eatwise/core/widget_bridge/widget_data_provider.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/fasting/presentation/fasting_presentation_test_helper.dart';
import '../../features/fasting/tz_test_helper.dart';

/// WidgetDataProvider 单测（《规格-M2》§8：传锚点不传剩余值；
/// 归属日口径 D-07，与计时主控同源）。
///
/// 时间线约定同 fasting_presentation_test_helper：Asia/Shanghai，16:8
/// （进食 12:00–20:00 本地）；本地 12:00 = UTC 04:00，20:00 = UTC 12:00。
void main() {
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  /// 固定文案解析器：把输入回显进标签，便于断言状态/归属日/墙钟的传递。
  WidgetDataProvider buildProvider() {
    return WidgetDataProvider(
      textResolver: (state, attribution, wallClock) => (
        statusLabel: 'status:${state.name}',
        noPlanLabel: 'noplan',
        dueLineLabel: wallClock == null ? null : 'due:$wallClock',
        attributionLabel: attribution == null
            ? null
            : 'attr:${attribution.toIsoString()}',
      ),
    );
  }

  WidgetFastingData compute({
    FastingPlan? plan = FastingPlan.plan16x8,
    ActiveCycleSnapshot? cycle,
    int? earlyEatEndUtc,
    required int nowUtcSec,
  }) {
    return buildProvider().compute(
      plan: plan,
      activeCycle: cycle,
      earlyEatEndUtc: earlyEatEndUtc,
      nowUtcSec: nowUtcSec,
      location: bjt,
    );
  }

  test('无方案 → noPlan，无锚点/归属日，仅引导文案', () {
    final data = compute(plan: null, nowUtcSec: bjtUtc(28, 0));

    expect(data.state, FastingState.noPlan);
    expect(data.targetAnchorUtcMs, isNull);
    expect(data.attributionDate, isNull);
    expect(data.planLabel, isNull);
    expect(data.statusLabel, 'status:noPlan');
    expect(data.noPlanLabel, 'noplan');
  });

  test('断食中：锚点 = 计划进食开始 UTC 毫秒，墙钟 12:00，归属日 = 当日', () {
    // 本地 07-28 08:00（UTC 00:00）断食中，目标 = 本地 12:00 = UTC 04:00。
    final data = compute(nowUtcSec: bjtUtc(28, 0));

    expect(data.state, FastingState.fasting);
    expect(data.targetAnchorUtcMs, bjtUtc(28, 4) * 1000);
    expect(data.targetWallClockLabel, '12:00');
    expect(data.dueLineLabel, 'due:12:00');
    expect(data.attributionDate, const LocalDate(2026, 7, 28));
    expect(data.attributionLabel, 'attr:2026-07-28');
    expect(data.planLabel, '16:8');
    expect(data.eatWindowLabel, '12:00–20:00');
    expect(data.extendedMinutes, 0);
  });

  test('跨午夜：凌晨断食中，锚点 = 当日中午，归属日 = 次日（B1）', () {
    // UTC 07-28 20:00 = 本地 07-29 04:00：断食中，目标 = 本地 07-29 12:00。
    final data = compute(nowUtcSec: bjtUtc(28, 20));

    expect(data.state, FastingState.fasting);
    expect(data.targetAnchorUtcMs, bjtUtc(29, 4) * 1000);
    expect(data.targetWallClockLabel, '12:00');
    expect(data.attributionDate, const LocalDate(2026, 7, 29));
    expect(data.attributionLabel, 'attr:2026-07-29');
  });

  test('进食中：锚点 = 进食窗口结束（20:00），归属日预计算 = 次日', () {
    // 本地 07-28 14:00（UTC 06:00）进食中。
    final data = compute(nowUtcSec: bjtUtc(28, 6));

    expect(data.state, FastingState.eating);
    expect(data.targetAnchorUtcMs, bjtUtc(28, 12) * 1000);
    expect(data.targetWallClockLabel, '20:00');
    expect(data.dueLineLabel, 'due:20:00');
    expect(data.attributionDate, const LocalDate(2026, 7, 29));
  });

  test('延长后：以持久化周期锚点为准，状态 fastingExtended（D-10）', () {
    final cycle = ActiveCycleSnapshot(
      startUtc: bjtUtc(27, 12),
      plannedEndUtc: bjtUtc(28, 4) + 30 * 60,
      eatWindowEndUtc: bjtUtc(28, 12) + 30 * 60,
      extendedMinutes: 30,
    );
    final data = compute(nowUtcSec: bjtUtc(28, 0), cycle: cycle);

    expect(data.state, FastingState.fastingExtended);
    expect(data.targetAnchorUtcMs, (bjtUtc(28, 4) + 30 * 60) * 1000);
    expect(data.targetWallClockLabel, '12:30');
    expect(data.extendedMinutes, 30);
  });

  test('提前破窗覆盖：按计划应断食的时段改判 eating，目标 = 进食结束锚点', () {
    // 本地 07-28 10:00（UTC 02:00）本应在断食，提前破窗覆盖生效中。
    final data = compute(
      nowUtcSec: bjtUtc(28, 2),
      earlyEatEndUtc: bjtUtc(28, 12),
    );

    expect(data.state, FastingState.eating);
    expect(data.targetAnchorUtcMs, bjtUtc(28, 12) * 1000);
    expect(data.targetWallClockLabel, '20:00');
  });
}

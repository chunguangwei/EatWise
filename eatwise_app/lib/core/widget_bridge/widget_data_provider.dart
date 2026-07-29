import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:timezone/timezone.dart' as tz;

/// 锁屏/桌面小组件数据计算（《规格-M2 断食计时状态机》§8「传锚点不传剩余值」）。
///
/// 同步总原则（§8）：小组件**不传输「剩余时间数值」**，只传输
/// 「目标锚点 UTC 毫秒 + 状态枚举」；倒计时由小组件侧系统级活控件
/// （iOS `Text(timerInterval:)` / Android `Chronometer`）自治渲染，天然零漂移，
/// App 内与小组件读同一锚点，误差 ≤1 分钟（§8.3）。
///
/// 共享内容仅限渲染必需的最小数据集（状态、锚点、归属日、窗口标签），
/// 健康明细不进共享存储（技术选型 §3 数据共享行，D-18 最小化）。

/// 小组件渲染数据（跨平台共享契约，键定义见 WidgetSyncService）。
final class WidgetFastingData {
  const WidgetFastingData({
    required this.state,
    required this.statusLabel,
    required this.noPlanLabel,
    this.targetAnchorUtcMs,
    this.targetWallClockLabel,
    this.dueLineLabel,
    this.attributionDate,
    this.attributionLabel,
    this.planLabel,
    this.eatWindowLabel,
    this.extendedMinutes = 0,
  });

  /// 应用级状态（§2.1）；`noPlan` 时无锚点。
  final FastingState state;

  /// 状态文案（已按当前语言本地化，D-15）。
  final String statusLabel;

  /// 无方案引导文案（本地化）。
  final String noPlanLabel;

  /// 倒计时目标锚点（UTC epoch **毫秒**；fasting → 计划进食开始，
  /// eating → 进食窗口结束）。小组件活控件据此自治倒计时。
  final int? targetAnchorUtcMs;

  /// 目标锚点的本地墙钟「HH:mm」（Android 2×2 降级显示「到点时刻」，
  /// 设计规范 §4.5）。
  final String? targetWallClockLabel;

  /// 到点整行文案（本地化、语序正确，如「12:00 可进食」/「Eat at 12:00」）。
  final String? dueLineLabel;

  /// 打卡归属日（D-07，`yyyy-MM-dd`）。
  final LocalDate? attributionDate;

  /// 归属日整行文案（本地化，如「本次断食计入 7月29日」）。
  final String? attributionLabel;

  /// 方案标识（如 `16:8`）。
  final String? planLabel;

  /// 进食窗口墙钟标签（如「12:00–20:00」）。
  final String? eatWindowLabel;

  /// 本周期累计延长分钟数（D-10）。
  final int extendedMinutes;

  @override
  bool operator ==(Object other) =>
      other is WidgetFastingData &&
      other.state == state &&
      other.statusLabel == statusLabel &&
      other.noPlanLabel == noPlanLabel &&
      other.targetAnchorUtcMs == targetAnchorUtcMs &&
      other.targetWallClockLabel == targetWallClockLabel &&
      other.dueLineLabel == dueLineLabel &&
      other.attributionDate == attributionDate &&
      other.attributionLabel == attributionLabel &&
      other.planLabel == planLabel &&
      other.eatWindowLabel == eatWindowLabel &&
      other.extendedMinutes == extendedMinutes;

  @override
  int get hashCode => Object.hash(
    state,
    statusLabel,
    noPlanLabel,
    targetAnchorUtcMs,
    targetWallClockLabel,
    dueLineLabel,
    attributionDate,
    attributionLabel,
    planLabel,
    eatWindowLabel,
    extendedMinutes,
  );
}

/// 小组件文案解析器（D-15：文案走 i18n key；生产实现由 slang 适配器提供，
/// 测试可注入固定文案）。
typedef WidgetTextResolver =
    ({
      String statusLabel,
      String noPlanLabel,
      String? dueLineLabel,
      String? attributionLabel,
    })
    Function(
      FastingState state,
      LocalDate? attributionDate,
      String? targetWallClock,
    );

/// 小组件数据纯函数计算：周期快照 + `anchorsFor`（经 `resolveState`）→
/// 小组件渲染数据。与计时主控同源（同一锚点、同一归属日口径），保证
/// App 内与小组件一致（§8.3）。
final class WidgetDataProvider {
  const WidgetDataProvider({required this.textResolver});

  final WidgetTextResolver textResolver;

  /// 计算当前小组件数据。
  ///
  /// - [plan] 为 null（NO_PLAN）时返回无锚点的引导态；
  /// - [activeCycle] 为持久化的进行中周期（含延长锚点，D-10 唯一真源）；
  /// - [earlyEatEndUtc] 为提前破窗后的当日进食结束锚点（T3/T4/T9）；
  /// - [nowUtcSec] 当前 UTC epoch 秒；[location] 设备时区（D-07 渲染入口）。
  WidgetFastingData compute({
    required FastingPlan? plan,
    required ActiveCycleSnapshot? activeCycle,
    required int? earlyEatEndUtc,
    required int nowUtcSec,
    required tz.Location location,
  }) {
    final texts = textResolver(FastingState.noPlan, null, null);
    if (plan == null) {
      return WidgetFastingData(
        state: FastingState.noPlan,
        statusLabel: texts.statusLabel,
        noPlanLabel: texts.noPlanLabel,
      );
    }

    // 状态落点（§4.2：内部经 anchorsFor 由窗口墙钟 + 时区换算 UTC 锚点）。
    var snapshot = resolveState(nowUtcSec, plan, location);

    // 提前破窗覆盖（T3/T4/T9：以实际破窗时刻为进食起点，当日进食结束
    // 锚点不后移〔假设〕）——与 FastingTimerController._resolve 同口径。
    if (earlyEatEndUtc != null && snapshot.nowUtc < earlyEatEndUtc) {
      snapshot = FastingSnapshot(
        state: FastingState.eating,
        nowUtc: snapshot.nowUtc,
        targetUtc: earlyEatEndUtc,
        attributionPreview: localDateOf(snapshot.nowUtc, location).addDays(1),
      );
    }

    // 持久化周期与重算周期同根时以持久化版本为准（含延长锚点，D-10）。
    FastCycle? cycle = snapshot.cycle;
    if (cycle != null &&
        activeCycle != null &&
        activeCycle.startUtc == cycle.startUtc) {
      cycle = activeCycle.toCycle();
      snapshot = FastingSnapshot(
        state: cycle.state,
        nowUtc: snapshot.nowUtc,
        cycle: cycle,
        targetUtc: cycle.plannedEndUtc,
        attributionPreview: snapshot.attributionPreview,
      );
    }

    final state = snapshot.state;
    final targetUtc = snapshot.targetUtc;
    final wallClock = targetUtc == null
        ? null
        : _formatWallClock(targetUtc, location);
    final attribution = snapshot.attributionPreview;
    final texts2 = textResolver(state, attribution, wallClock);

    return WidgetFastingData(
      state: state,
      statusLabel: texts2.statusLabel,
      noPlanLabel: texts2.noPlanLabel,
      targetAnchorUtcMs: targetUtc == null ? null : targetUtc * 1000,
      targetWallClockLabel: wallClock,
      dueLineLabel: texts2.dueLineLabel,
      attributionDate: attribution,
      attributionLabel: texts2.attributionLabel,
      planLabel: plan.id,
      eatWindowLabel: _eatWindowLabel(plan),
      extendedMinutes: cycle?.extendedMinutes ?? 0,
    );
  }

  /// 目标锚点 → 本地墙钟「HH:mm」（§3.1：渲染唯一入口 toLocal）。
  static String _formatWallClock(int utcSec, tz.Location location) {
    final dt = toLocal(utcSec, location);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 进食窗口墙钟标签「HH:mm–HH:mm」（方案存本地墙钟表达，§3.1）。
  static String _eatWindowLabel(FastingPlan plan) {
    String fmt(int minutes) {
      final h = (minutes ~/ 60).toString().padLeft(2, '0');
      final m = (minutes % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }

    return '${fmt(plan.eatStartMinutes)}–${fmt(plan.eatEndMinutes)}';
  }
}

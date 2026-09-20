import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/notification/local_notification_service.dart';
import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/widget_bridge/widget_sync_service.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// 断食计时状态接线（《规格-M2》§2.3 迁移表的运行时胶水层）。
///
/// 纪律：全部业务判定（落点/归属日/达标/延长上限）委托 domain 纯函数
/// （`resolveState` / `manualEndFast` / `extendCycle` / `completeCycleOnTime` /
/// `reconcile`），本层只负责「注入时钟 → 调纯函数 → 持久化快照 →
/// 调 [FastingNotificationScheduler.reschedule] 单入口 → 刷新 UI 状态」。

/// 本地通知服务（生产实现；main 中 override 为已 initialize 的实例）。
final localNotificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService();
});

/// 已登记待生效的换方案（T12，D-06）；无 pending 时为 null。
///
/// watch [planVersionProvider]：一键启动/换方案登记/取消都会 +1，横幅
/// 随之刷新（onboardingStoreProvider 是存储句柄，watch 它不随键值写入重建）。
final pendingPlanProvider = Provider<PendingPlan?>((ref) {
  ref.watch(planVersionProvider);
  return ref.read(onboardingStoreProvider).loadPendingPlan();
});

/// 断食通知调度器（单 reschedule 入口，§7.2.3）。
///
/// 文案经 slang 适配器解析（D-15）；语言切换后新文案在下一次重排生效。
final fastingNotificationSchedulerProvider =
    Provider<FastingNotificationScheduler>((ref) {
      final t = LocaleSettings.currentLocale.buildSync();
      return FastingNotificationScheduler(
        notifications: ref.watch(localNotificationServiceProvider),
        textResolver: slangFastingNotificationTextResolver(t),
        channel: fastingReminderChannel(t),
        locationResolver: () => ref.read(deviceLocationProvider),
      );
    });

/// 周期快照存储（默认 SharedPreferences 实现；测试 override 内存实现）。
final fastingCycleStoreProvider = Provider<FastingCycleStore>((ref) {
  return SharedPreferencesFastingCycleStore(
    ref.watch(sharedPreferencesProvider),
  );
});

/// 计时器时钟（UTC epoch 秒；测试 override 注入假时钟）。
final fastingClockProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
});

/// 周期关闭（达标/不达标）钩子（M5 streak 接线）：默认转发给
/// [StreakController.onFastClosed]（落 drift + 本地推演 + F2 上行后拉 S1 对账）；
/// 失败静默降级，不阻断计时主流程（四态规范：本地计算永不等网络）。
final fastingStreakHookProvider =
    Provider<FutureOr<void> Function(FastingRecord record)>((ref) {
      return (record) async {
        try {
          await ref
              .read(streakControllerProvider.notifier)
              .onFastClosed(record);
        } on Object {
          // streak 依赖未注入/网络失败：计时主流程不受影响，恢复后对账。
        }
      };
    });

/// 断食计时主页状态。
final class FastingTimerState {
  const FastingTimerState({
    required this.plan,
    required this.snapshot,
    required this.celebrating,
    this.lastClosedRecord,
  });

  /// 无方案态（NO_PLAN，§3.4：显示引导启动方案，不显示倒计时）。
  const FastingTimerState.noPlan()
    : plan = null,
      snapshot = null,
      celebrating = false,
      lastClosedRecord = null;

  /// 当前方案（null = 无方案）。
  final FastingPlan? plan;

  /// 状态落点快照（含延长还原后的周期；无方案时为 null）。
  final FastingSnapshot? snapshot;

  /// 破壳庆祝展示中（设计稿 §5.1-1：归零/结束断食且达标时触发）。
  final bool celebrating;

  /// 最近关闭的周期记录（达标判定/归属日供 UI 与后续 streak 消费）。
  final FastingRecord? lastClosedRecord;

  /// 当前应用级状态（§2.1）。
  FastingState get state =>
      plan == null ? FastingState.noPlan : snapshot!.state;

  /// 当前进行中的 FastCycle（仅断食态非空）。
  FastCycle? get cycle => snapshot?.cycle;

  FastingTimerState copyWith({
    FastingPlan? plan,
    FastingSnapshot? snapshot,
    bool? celebrating,
    FastingRecord? lastClosedRecord,
  }) {
    return FastingTimerState(
      plan: plan ?? this.plan,
      snapshot: snapshot ?? this.snapshot,
      celebrating: celebrating ?? this.celebrating,
      lastClosedRecord: lastClosedRecord ?? this.lastClosedRecord,
    );
  }
}

/// 断食计时控制器：每秒 tick 刷新倒计时，动作委托 domain 纯函数。
final class FastingTimerController extends Notifier<FastingTimerState> {
  FastingCycleStore get _store => ref.read(fastingCycleStoreProvider);

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  int _now() => ref.read(fastingClockProvider)();

  tz.Location get _location => ref.read(deviceLocationProvider);

  /// 上次小组件同步的分钟序号（tick 跨分钟边界判定用，-1 = 未同步）。
  int _lastWidgetSyncMinute = -1;

  /// 小组件刷新（《规格-M2》§8：与通知 reschedule 挂同一触发链）。
  ///
  /// 数据由 WidgetDataProvider 从「周期快照 + anchorsFor」重算，
  /// 与计时主控同源；WidgetSyncService 内部 diff 跳过 + 失败降级，
  /// 不阻断计时主流程。
  void _syncWidget(FastingPlan? plan) {
    final data = ref
        .read(widgetDataProviderProvider)
        .compute(
          plan: plan,
          activeCycle: _store.loadActiveCycle(),
          earlyEatEndUtc: _store.loadEarlyEatEndUtc(),
          nowUtcSec: _now(),
          location: _location,
        );
    _lastWidgetSyncMinute = _now() ~/ 60;
    unawaited(ref.read(widgetSyncServiceProvider).sync(data));
  }

  @override
  FastingTimerState build() {
    // 方案写入信号量：一键启动/换方案登记时 +1（onboardingStoreProvider 是
    // 普通 Provider，watch 它不会因键值写入触发重建）。
    ref.watch(planVersionProvider);
    final onboardStore = ref.read(onboardingStoreProvider);
    // T13 兜底转正（§4.1）：pendingPlan 到点（本地 0:00 已过）先生效再读
    // 方案，覆盖杀进程后首开 / 0:00 后首次 build 的场景。
    final activated = _activatePendingPlanIfDue(onboardStore);
    final plan = activated ?? onboardStore.loadActivePlan()?.plan;
    if (plan == null) {
      _syncWidget(null);
      return const FastingTimerState.noPlan();
    }
    final now = _now();

    // T16 APP_FOREGROUND 对账副作用（§7.2.3）：回前台/重启恢复一律全量
    // 重排——此前只在状态迁移时重排，App 存活超过 48h 通知视界会耗尽。
    // 重排幂等（先 cancelAll 再重建），build 高频触发无妨；T13 转正路径
    // 已按 planActivate 重排，不重复。
    if (activated == null) {
      _reschedule(
        plan,
        _store.loadActiveCycle()?.extendedMinutes ?? 0,
        RescheduleReason.appForeground,
      );
    }

    // 重启恢复对账（T16 APP_FOREGROUND，§6-B12/B13）：
    // 持久化的进行中周期若在离线期间跨过窗口边界，按 T2/T8 规则补关闭——
    // 周期关闭不依赖前台；达标周期补一次破壳庆祝（设计稿 §5.1-1）。
    final stored = _store.loadActiveCycle();
    if (stored != null && stored.plannedEndUtc <= now) {
      final result = reconcile(
        openCycles: <FastCycle>[stored.toCycle()],
        nowUtc: now,
        plan: plan,
        location: _location,
      );
      _store.clearActiveCycle();
      final closed = result.closedRecords.isEmpty
          ? null
          : result.closedRecords.last;
      // 重启恢复补关闭的周期：逐条触发 streak 接线（落库/推演/上行）。
      for (final record in result.closedRecords) {
        _emitClosed(record, plan);
      }
      _syncWidget(plan);
      return _resolve(
        plan,
        result.snapshot,
        celebrating: closed?.qualified ?? false,
        lastClosed: closed,
      );
    }
    _syncWidget(plan);
    return _resolve(plan, resolveState(now, plan, _location));
  }

  /// T13：pendingPlan 到期（本地 0:00 已过）则转正，返回新方案；
  /// 无 pending 或未到期返回 null。
  ///
  /// 进行中周期口径：旧方案的 activeCycle **作废、不写 FastingRecord**——
  /// T13 规定当前区间按新方案锚点重算落点（「当前时刻之后最近的窗口
  /// 边界」原则），若按旧锚点补关闭，会把一条归属旧窗口的「幽灵记录」
  /// （甚至幽灵达标）写进 streak。历史已关闭记录保留不回算（D-06）。
  FastingPlan? _activatePendingPlanIfDue(OnboardingStore onboardStore) {
    final pending = onboardStore.loadPendingPlan();
    if (pending == null) return null;
    final now = _now();
    final plan = activatePendingPlan(pending, now);
    if (plan == null) return null;
    final snapshot = resolveState(now, plan, _location);
    onboardStore.saveActivePlan(
      ActivePlanSnapshot(
        plan: plan,
        initialState: snapshot.state.name,
        targetUtc: snapshot.targetUtc,
        attributionDate: snapshot.attributionPreview?.toIsoString(),
        startedAtUtc: now,
      ),
    );
    onboardStore.clearPendingPlan();
    ref.invalidate(pendingPlanProvider); // 转正后横幅随之消失
    _store.clearActiveCycle(); // 作废进行中周期（口径见函数注释）
    _store.clearEarlyEatEndUtc(); // 旧方案的提前破窗覆盖一并作废
    _reschedule(plan, 0, RescheduleReason.planActivate);
    // T13 转正 = 服务端视角的「改动生效」落地：置脏并尽力上行一次，
    // 保证服务端 current 与本地生效方案收敛（失败由同步引擎重试）。
    ref.read(fastingPlanSyncProvider)?.markDirtyAndTryFlush(plan);
    return plan;
  }

  /// 用落点快照重建状态；持久化周期与重算周期同根（同一断食开始锚点）
  /// 时以持久化版本为准——它是含延长锚点的唯一真源（D-10）。
  FastingTimerState _resolve(
    FastingPlan plan,
    FastingSnapshot snapshot, {
    bool celebrating = false,
    FastingRecord? lastClosed,
  }) {
    var effective = snapshot;

    // 提前破窗覆盖（T3/T4/T9：以实际破窗时刻作为进食窗口起点，当日进食
    // 结束锚点不后移〔假设〕）。resolveState 只按计划锚点落点，会把
    // 「提前破窗后、计划进食开始前」的区间误判回 fasting，这里按持久化的
    // 破窗覆盖改判 EATING，倒计时 = 距当日进食窗口结束；回到计划轨道
    // （now 越过结束锚点，新周期已由锚点推导）后清除覆盖。
    final earlyEatEnd = _store.loadEarlyEatEndUtc();
    if (earlyEatEnd != null) {
      if (snapshot.nowUtc < earlyEatEnd) {
        effective = FastingSnapshot(
          state: FastingState.eating,
          nowUtc: snapshot.nowUtc,
          targetUtc: earlyEatEnd,
          // 下一次断食计入「下一进食窗口」的自然日（D-07）。
          attributionPreview: localDateOf(
            snapshot.nowUtc,
            _location,
          ).addDays(1),
        );
      } else {
        _store.clearEarlyEatEndUtc();
      }
    }

    final cycle = effective.cycle;
    if (cycle != null) {
      final stored = _store.loadActiveCycle();
      if (stored != null && stored.startUtc == cycle.startUtc) {
        final restored = stored.toCycle();
        effective = FastingSnapshot(
          state: restored.state,
          nowUtc: effective.nowUtc,
          cycle: restored,
          targetUtc: restored.plannedEndUtc,
          attributionPreview: effective.attributionPreview,
        );
      }
    }
    return FastingTimerState(
      plan: plan,
      snapshot: effective,
      celebrating: celebrating,
      lastClosedRecord: lastClosed,
    );
  }

  /// 每秒 tick：刷新倒计时；断食锚点到点（归零）时按 T2/T8 自动关闭
  /// 周期 → COMPLETED_* → 破壳庆祝 → 重排通知（§2.3 副作用链）。
  void tick() {
    final plan = state.plan;
    if (plan == null) return;
    final now = _now();
    // T13：前台跨过本地 0:00 时由每秒 tick 兜底转正（杀进程场景由
    // build 对账转正）；转正后当前区间按新方案锚点重算落点。
    final activated = _activatePendingPlanIfDue(
      ref.read(onboardingStoreProvider),
    );
    if (activated != null) {
      state = _resolve(activated, resolveState(now, activated, _location));
      _syncWidget(activated);
      return;
    }
    final cycle = state.cycle;
    if (cycle != null && now >= cycle.plannedEndUtc) {
      final record = completeCycleOnTime(cycle, _location);
      _store.clearActiveCycle();
      _emitClosed(record, plan);
      // 状态机迁移埋点（§3.2：自动到点 fasting→eating）。
      _analytics.track(
        'fasting_state_change',
        properties: <String, Object?>{
          'from_state': 'fasting',
          'to_state': 'eating',
          'trigger': 'auto',
          'attribute_date': record.date,
        },
      );
      _reschedule(plan, 0, RescheduleReason.stateTransition);
      state = _resolve(
        plan,
        resolveState(now, plan, _location),
        celebrating: record.qualified,
        lastClosed: record,
      );
      _syncWidget(plan);
      return;
    }
    // tick 跨分钟边界：小组件数据为锚点制，正常 diff 会跳过平台调用；
    // 此处兜底保证延长/时区变化等旁路改动 1 分钟内收敛（§8.3 误差 ≤1 分钟）。
    final minute = now ~/ 60;
    if (minute != _lastWidgetSyncMinute) {
      _syncWidget(plan);
    }
    state = _resolve(plan, resolveState(now, plan, _location));
  }

  /// 「结束断食」按钮点击（§3.2 fasting_end_click）：打开两步确认弹窗前
  /// 上报；属性口径与 [endFast] 的 confirm 事件一致。
  void trackEndFastClick() {
    _analytics.track('fasting_end_click', properties: _endFastProps());
  }

  /// 确认弹窗「继续断食」（取消结束，§3.2 fasting_end_cancel）。
  void trackEndFastCancel() {
    _analytics.track('fasting_end_cancel', properties: _endFastProps());
  }

  /// D-08 预判：此刻手动结束是否达标（false = 弹窗展示不达标警示）。
  bool wouldEndQualify() {
    final cycle = state.cycle;
    if (cycle == null) return true;
    return wouldManualEndQualify(cycle, _now());
  }

  /// 结束断食事件私有属性（§3.2：elapsed/planned/early 口径同字典）。
  Map<String, Object?> _endFastProps() {
    final cycle = state.cycle;
    if (cycle == null) return const <String, Object?>{};
    final now = _now();
    return <String, Object?>{
      'elapsed_ms': (now - cycle.startUtc) * 1000,
      'planned_ms': cycle.plannedSec * 1000,
      'early_minutes': now >= cycle.plannedEndUtc
          ? 0
          : ((cycle.plannedEndUtc - now) ~/ 60),
    };
  }

  /// 手动「结束断食」（T3/T4/T9；D-08 容差判定在 domain）。
  /// EATING 下按钮置灰、事件防御性丢弃（T11）。
  ///
  /// 由确认弹窗「确认结束」触发（两步确认，§3.2：click 在打开弹窗时
  /// 由 [trackEndFastClick] 上报，confirm 在此上报）。
  void endFast() {
    final plan = state.plan;
    final cycle = state.cycle;
    if (plan == null || cycle == null) return;
    final now = _now();
    _analytics.track('fasting_end_confirm', properties: _endFastProps());
    final record = manualEndFast(cycle, now, _location);
    _analytics.track(
      'fasting_state_change',
      properties: <String, Object?>{
        'from_state': 'fasting',
        'to_state': 'eating',
        'trigger': 'manual_end',
        'attribute_date': record.date,
      },
    );
    _store.clearActiveCycle();
    _emitClosed(record, plan);
    // T3/T4/T9：进食窗口以实际破窗时刻开启，终点 = 破窗时刻 + 计划进食
    // 窗口时长（封顶本周期计划进食结束锚点）。修复：此前直接取
    // cycle.eatWindowEndUtc，在「进食窗已关闭后的断食段」破窗时会把进食
    // 终点算到次日计划窗末（倒计时 ~24h，冒烟 C3 复现）。
    final eatWindowLenSec = cycle.eatWindowEndUtc - cycle.plannedEndUtc;
    final earlyEatEndUtc = now + eatWindowLenSec < cycle.eatWindowEndUtc
        ? now + eatWindowLenSec
        : cycle.eatWindowEndUtc;
    _store.saveEarlyEatEndUtc(earlyEatEndUtc);
    _reschedule(plan, 0, RescheduleReason.manualEndFast);
    state = _resolve(
      plan,
      resolveState(now, plan, _location),
      celebrating: record.qualified,
      lastClosed: record,
    );
    _syncWidget(plan);
  }

  /// 「延长」一步（T5/T6/T7：步进 30min、单周期累计上限 4h，D-10）。
  ///
  /// 已达上限或当前非断食态返回 false（按钮置 disabled + 提示，T7）。
  bool extend() {
    final plan = state.plan;
    final cycle = state.cycle;
    if (plan == null || cycle == null) return false;
    final extended = extendCycle(cycle);
    if (extended == null) return false;
    _store.saveActiveCycle(ActiveCycleSnapshot.fromCycle(extended));
    // 延长埋点（§3.2 fasting_extend_click；D-10 步进 30 分钟）。
    _analytics.track(
      'fasting_extend_click',
      properties: <String, Object?>{
        'extend_minutes': extended.extendedMinutes - cycle.extendedMinutes,
        'extend_count_today': extended.extendedMinutes ~/ kExtendStepMinutes,
      },
    );
    _reschedule(
      plan,
      extended.extendedMinutes,
      RescheduleReason.extensionApplied,
    );
    state = _resolve(plan, resolveState(_now(), plan, _location));
    _syncWidget(plan);
    return true;
  }

  /// 关闭破壳庆祝（动画播完或用户点按）。
  void dismissCelebration() {
    if (state.celebrating) {
      state = state.copyWith(celebrating: false);
    }
  }

  /// 周期关闭统一出口：转发 streak 钩子（M5，失败不阻断计时主流程）；
  /// 上报 `fasting_checkin_success`（§3.2 核心事件，§1.5 立即上报）。
  void _emitClosed(FastingRecord record, FastingPlan plan) {
    _analytics.track(
      'fasting_checkin_success',
      properties: <String, Object?>{
        'attribute_date': record.date,
        'is_qualified': record.qualified,
        'actual_ms': record.actualSec * 1000,
        'planned_ms': record.plannedSec * 1000,
        'plan_type': plan.id.replaceAll(':', '_'),
        'break_reason': record.qualified ? 'none' : 'early_end',
      },
      flushNow: true,
    );
    unawaited(Future.sync(() => ref.read(fastingStreakHookProvider)(record)));
  }

  void _reschedule(FastingPlan plan, int extensionMinutes, RescheduleReason r) {
    unawaited(
      ref
          .read(fastingNotificationSchedulerProvider)
          .reschedule(
            plan: plan,
            extensionMinutes: extensionMinutes,
            reason: r,
          ),
    );
  }
}

/// 断食计时控制器 Provider。
final fastingTimerControllerProvider =
    NotifierProvider<FastingTimerController, FastingTimerState>(
      FastingTimerController.new,
    );

/// 断食计时进行中（fasting/fastingExtended）——记录页「断食期用餐」
/// 标记用（阶段 C：饮食记录入账时读取，写入 FoodEntry.duringFast 本地属性）。
/// 计时链路未装配（测试/预览）时按非断食态兜底（与 currentUserIdProvider 同口径）。
final isFastingInProgressProvider = Provider<bool>((ref) {
  try {
    final state = ref.watch(fastingTimerControllerProvider).state;
    return state == FastingState.fasting ||
        state == FastingState.fastingExtended;
  } on Object {
    return false;
  }
});

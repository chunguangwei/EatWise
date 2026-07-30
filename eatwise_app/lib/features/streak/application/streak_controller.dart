import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart' hide FastingRecord;
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// streak UI 状态（首页横幅 / 断签弹窗 / 里程碑徽章 / 我的页卡片共用）。
final class StreakUiState {
  const StreakUiState({
    required this.status,
    required this.currentStreak,
    required this.longestStreak,
    required this.mendCardBalance,
    required this.mendVisualState,
    required this.pendingMendDates,
    required this.unlockedMilestones,
    required this.fromServer,
    this.justUnlockedMilestone,
    this.pendingBreakPopupDate,
  });

  /// 状态机四态（§2.1）。
  final StreakStatus status;

  /// 当前连胜（fromServer=true 时为服务端权威值，否则本地推演值）。
  final int currentStreak;

  /// 历史最长连胜。
  final int longestStreak;

  /// 当月补签卡库存（0–2）。
  final int mendCardBalance;

  /// 补签卡三态（§3.2）。
  final MendCardVisualState mendVisualState;

  /// 7 天窗口内未补签断签日（本地推演；服务端 S1 不返回断签日〔假设〕）。
  final List<String> pendingMendDates;

  /// 已解锁里程碑档位。
  final Set<int> unlockedMilestones;

  /// 数据来源：true=服务端权威（S1 对账后）；false=本地推演（离线）。
  final bool fromServer;

  /// 刚解锁待展示的里程碑（徽章滑入触发；消费后需 [StreakController.consumeMilestone]）。
  final int? justUnlockedMilestone;

  /// 待自动弹出的断签日（频控：每断签日只自动弹 1 次，§4.1）。
  final String? pendingBreakPopupDate;
}

/// 本地存储（生产 SharedPreferences；未注入场景降级内存，不阻断主流程）。
final streakLocalStoreProvider = Provider<StreakLocalStore>((ref) {
  try {
    return SharedPreferencesStreakLocalStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryStreakLocalStore();
  }
});

/// streak 服务端接口（dio 装配见 core/network）。
final streakApiProvider = Provider<StreakApi>((ref) {
  return StreakApi(ref.watch(apiDioProvider));
});

/// 断食打卡上报接口（F1/F2，达标事件上行供服务端重算 streak）。
final fastingReportApiProvider = Provider<FastingReportApi>((ref) {
  return FastingReportApi(ref.watch(apiDioProvider));
});

/// 今日自然日（yyyy-MM-dd，设备时区；测试 override 注入固定日期）。
final streakTodayProvider = Provider<String Function()>((ref) {
  return () {
    tz.Location location;
    try {
      location = ref.read(deviceLocationProvider);
    } on Object {
      location = tz.UTC;
    }
    final now = tz.TZDateTime.now(location);
    return isoOf(DateTime.utc(now.year, now.month, now.day));
  };
});

/// streak 控制器（《规格-M5》：服务端 S1 权威 + 本地引擎离线推演）。
///
/// 接线纪律（§2.4 冲突原则）：
/// - 本地先算先展示（乐观）：达标/结算即时入账本地引擎，UI 不等网络；
/// - 服务端为权威：拉到 S1/S3 后覆盖对账（LWW 语义，D-20）；
/// - 离线推演：网络失败保留本地结果并标 fromServer=false，恢复后
///   [refreshFromServer] 以对账为准。
final class StreakController extends Notifier<StreakUiState> {
  StreakEngine get _engine => _engineRef ??= _loadEngine();
  StreakEngine? _engineRef;

  StreakLocalStore get _store => ref.read(streakLocalStoreProvider);

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  String _today() => ref.read(streakTodayProvider)();

  /// 服务端权威值缓存（S1 对账后非空）。
  int? _serverCurrentStreak;

  StreakEngine _loadEngine() => _store.loadEngine() ?? StreakEngine();

  @override
  StreakUiState build() {
    // 启动补结算（§2.4：本地 0 点结算为主，App 启动时对未结算日补结算）。
    final settlement = _engine.settleUpTo(_today());
    if (settlement.newlyMissed.isNotEmpty ||
        settlement.newlyBroken.isNotEmpty) {
      _store.saveEngine(_engine);
    }
    unawaited(refreshFromServer());
    return _uiState(fromServer: false, newlyMissed: settlement.newlyMissed);
  }

  /// 跨天结算入口（首页每秒 tick 调用；日内幂等，仅在跨过本地 0 点时生效）。
  void settleIfNeeded() {
    final today = _today();
    if (_engine.lastSettledDate == addDaysToIsoDate(today, -1)) return;
    final settlement = _engine.settleUpTo(today);
    _store.saveEngine(_engine);
    state = _uiState(
      fromServer: state.fromServer,
      newlyMissed: settlement.newlyMissed,
    );
  }

  /// 断食周期关闭入口（fasting 计时流钩子）：达标 → DAY_ACHIEVED（T1/T2/T8/T9），
  /// 不达标 → 仅落库（T10：归零发生在次日 0 点结算）。
  ///
  /// 副作用：① FastingRecord 落 drift（M6 趋势数据源）；② 本地引擎即时更新；
  /// ③ 尽力上行 F2 后拉 S1 对账（离线跳过，恢复后 [refreshFromServer]）。
  Future<void> onFastClosed(FastingRecord record) async {
    final today = _today();
    var milestones = const <int>[];
    if (record.qualified) {
      milestones = _engine.applyDayAchieved(record.date, today: today);
    }
    _store.saveEngine(_engine);
    await _persistRecord(record);
    state = _uiState(fromServer: state.fromServer, newMilestones: milestones);
    unawaited(_reportAndRefresh(record));
  }

  /// FastingRecord 落 drift（幂等：同归属日 upsert；无库注入时跳过）。
  Future<void> _persistRecord(FastingRecord record) async {
    AppDatabase? db;
    try {
      db = ref.read(appDatabaseProvider);
    } on Object {
      return; // 未注入数据库（测试/预览场景）：跳过持久化，不阻断计时流
    }
    if (db == null) return;
    final userId = ref.read(currentUserIdProvider);
    final requestId =
        _store.loadReportRequestId(record.date) ?? newClientRequestId();
    _store.saveReportRequestId(record.date, requestId);
    await db.fastingRecordDao.upsertRecord(
      FastingRecordsCompanion(
        localId: Value('$userId-${record.date}'),
        userId: Value(userId),
        attributionDate: Value(record.date),
        startUtc: Value(record.startUtc),
        endUtc: Value(record.endUtc),
        actualSec: Value(record.actualSec),
        plannedSec: Value(record.plannedSec),
        extendedMinutes: Value(record.extendedMinutes),
        result: Value(record.result.name),
        qualified: Value(record.qualified),
        clientRequestId: Value(requestId),
        syncStatus: const Value(SyncStatus.pending),
        createdAtUtc: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  /// 达标事件上行（F1 物化进行中记录 → F2 结束上报，幂等键稳定复用）
  /// 后拉 S1/S3 对账；任一环节失败保留本地推演（离线，§2.4 服务端兜底）。
  Future<void> _reportAndRefresh(FastingRecord record) async {
    try {
      final report = ref.read(fastingReportApiProvider);
      final active = await report.fetchActiveFast();
      if (active != null) {
        final requestId =
            _store.loadReportRequestId(record.date) ?? newClientRequestId();
        _store.saveReportRequestId(record.date, requestId);
        await report.reportEnd(
          clientRequestId: requestId,
          recordId: active.id,
          endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            record.endUtc * 1000,
            isUtc: true,
          ),
        );
        await _markRecordSynced(record);
      }
    } on Object {
      // 未物化/网络失败不阻断：服务端兜底结算为准（§2.4），恢复后对账。
    }
    await refreshFromServer();
  }

  Future<void> _markRecordSynced(FastingRecord record) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final userId = ref.read(currentUserIdProvider);
      await db.fastingRecordDao.updateSyncStatus(
        '$userId-${record.date}',
        SyncStatus.synced,
      );
    } on Object {
      // 状态回写失败不影响主流程。
    }
  }

  /// 拉取 S1/S3 对账（服务端权威覆盖，§2.4 冲突原则）。
  Future<void> refreshFromServer() async {
    try {
      final api = ref.read(streakApiProvider);
      final view = await api.fetchStreak();
      final milestones = await api.fetchMilestones();
      _reconcile(view, milestones);
    } on Object {
      // 离线：保留本地推演，fromServer 维持 false。
    }
  }

  void _reconcile(ServerStreakView view, List<ServerMilestone> milestones) {
    // 服务端权威：当前连胜/最长连胜/补签卡库存覆盖本地推演。
    _serverCurrentStreak = view.currentStreak;
    final engine = _engine;
    if (view.longestStreak > engine.longestStreak) {
      engine.longestStreak = view.longestStreak;
    }
    engine.alignMendCards(
      month: view.mendCardMonth,
      balance: view.mendCardStock,
      used: view.usedThisMonth,
    );
    final serverMilestones = milestones.map((m) => m.days).toSet();
    final newly = serverMilestones.difference(engine.unlockedMilestones);
    engine.unlockedMilestones.addAll(serverMilestones);
    _store.saveEngine(engine);
    state = _uiState(fromServer: true, newMilestones: newly.toList()..sort());
  }

  /// USE_MEND_CARD（T6）：在线走 S2（服务端强制窗口/库存规则）；
  /// 离线时本地推演先行，恢复后以服务端对账为准（〔假设〕乐观补签）。
  Future<MendResult> useMendCard(String date) async {
    final today = _today();
    try {
      final view = await ref
          .read(streakApiProvider)
          .useMendCard(clientRequestId: newClientRequestId(), date: date);
      // S2 成功：本地账本同步推进（断签日 → MENDED，链式重算 §2.5）。
      final result = _engine.useMendCard(date, today: today);
      _serverCurrentStreak = view.currentStreak;
      _engine.alignMendCards(
        month: view.mendCardMonth,
        balance: view.mendCardStock,
        used: view.usedThisMonth,
      );
      _store.saveEngine(_engine);
      state = _uiState(fromServer: true, newMilestones: result.newMilestones);
      _trackMendCardUsed();
      return result;
    } on BusinessApiException {
      rethrow; // 服务端业务拒绝（窗口外/已用/库存空）原样上抛给 UI 提示
    } on ApiException {
      // 离线（网络/超时）：本地推演先行，恢复后 refreshFromServer 对账为准。
      final result = _engine.useMendCard(date, today: today);
      _store.saveEngine(_engine);
      state = _uiState(fromServer: false, newMilestones: result.newMilestones);
      _trackMendCardUsed();
      return result;
    }
  }

  /// 补签卡使用回填（§3.5 streak_break_dialog_expose.use_card 点击后回填）。
  void _trackMendCardUsed() {
    _analytics.track(
      'streak_break_dialog_expose',
      properties: const <String, Object?>{
        'card_state': 'available',
        'use_card': true,
      },
    );
  }

  /// 补签预览：假设 [date] 补签成功后的当前连胜（弹窗 CTA 文案用）。
  int previewMendRestore(String date) {
    return _engine.previewMendRestore(date, today: _today());
  }

  /// 断签弹窗已展示（频控落库：每断签日只自动弹 1 次，§4.1）。
  void markBreakPopupShown(String missedDate) {
    _store.markBreakPopupShown(missedDate);
    if (state.pendingBreakPopupDate == missedDate) {
      state = _uiState(fromServer: state.fromServer, clearBreakPopup: true);
    }
  }

  /// 里程碑徽章已展示（清除滑入触发位）。
  void consumeMilestone() {
    if (state.justUnlockedMilestone != null) {
      state = _uiState(fromServer: state.fromServer, clearMilestone: true);
    }
  }

  StreakUiState _uiState({
    required bool fromServer,
    List<String> newlyMissed = const [],
    List<int> newMilestones = const [],
    bool clearBreakPopup = false,
    bool clearMilestone = false,
  }) {
    final today = _today();
    final engine = _engine;
    final shown = _store.loadShownBreakPopups();
    final unshown = newlyMissed.where((d) => !shown.contains(d));
    final popupDate = unshown.isEmpty ? null : unshown.first;
    // badge_reach（§3.5）不在此处上报：字典触发时机为「徽章展示」，
    // 由首页 MilestoneBadge 的 ExposureTracker 组件级曝光收口（≥50%+500ms）。
    return StreakUiState(
      status: engine.status(today),
      currentStreak: fromServer
          ? (_serverCurrentStreak ?? engine.currentStreak(today))
          : engine.currentStreak(today),
      longestStreak: engine.longestStreak,
      mendCardBalance: engine.mendCardBalance,
      mendVisualState: engine.mendCardVisualState(today),
      pendingMendDates: engine.pendingMendDates.toList()..sort(),
      unlockedMilestones: Set.of(engine.unlockedMilestones),
      fromServer: fromServer,
      justUnlockedMilestone: clearMilestone
          ? null
          : newMilestones.isNotEmpty
          ? newMilestones.first
          : stateOrNull?.justUnlockedMilestone,
      pendingBreakPopupDate: clearBreakPopup
          ? null
          : popupDate ?? stateOrNull?.pendingBreakPopupDate,
    );
  }
}

/// streak 控制器 Provider。
final streakControllerProvider =
    NotifierProvider<StreakController, StreakUiState>(StreakController.new);

/// 当前用户 ID（未登录为 anonymous；与 FoodEntry 同口径）。
final currentUserIdProvider = Provider<String>((ref) {
  try {
    return ref.watch(authControllerProvider).userId ?? 'anonymous';
  } on Object {
    return 'anonymous';
  }
});

/// UUIDv4 幂等键（客户端生成，D-20 / §2.2）。
String newClientRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

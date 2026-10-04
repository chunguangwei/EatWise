import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart' hide FastingRecord;
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/utils/client_request_id.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_result_mapping.dart'
    show localResultNameOf;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show recordSyncEngineProvider;
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

export 'package:eatwise/core/utils/client_request_id.dart';

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
    this.serverBreakNoticeDate,
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

  /// 服务端对账判分断签的待告知日（v1.13.27：服务端把本地认为达标的周期
  /// 判为不达标导致 streak 下降，而本地无断签弹窗时，首页 SnackBar 补一次
  /// 带日期的告知，防「连胜莫名归零」；一次性，消费后由
  /// [StreakController.consumeServerBreakNotice] 清除）。
  final String? serverBreakNoticeDate;
}

/// 本地存储（生产 SharedPreferences，键按当前用户命名空间；未注入场景
/// 降级内存，不阻断主流程）。构造期一次性迁移旧全局键（审计#6）。
final streakLocalStoreProvider = Provider<StreakLocalStore>((ref) {
  try {
    return SharedPreferencesStreakLocalStore(
      ref.watch(sharedPreferencesProvider),
      userId: ref.watch(currentUserIdProvider),
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

  /// 数据页触发的历史回填每会话只尝试一次（30 天窗口有缺才发请求）。
  bool _historyBackfillAttempted = false;

  StreakEngine _loadEngine() => _store.loadEngine() ?? StreakEngine();

  /// 数据页断食趋势回填触发口（v1.14.x：趋势窗口扩到 30 天，启动时的
  /// [refreshFromServer] 回填若撞上离线窗口，进入数据页时本地历史仍有
  /// 缺口）。本地近 30 天有缺口才复用 [_backfillRecentFastingRecords]
  /// 通道补一次（幂等只补缺，不造新端点），每会话最多一次；无缺口/
  /// 未登录/未装配直接返回。失败静默。
  Future<void> ensureFastingHistoryBackfilled() async {
    if (_historyBackfillAttempted) return;
    _historyBackfillAttempted = true;
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == 'anonymous') return; // 未登录无服务端历史可补
      final db = ref.read(appDatabaseProvider);
      final today = _today();
      final covered = <String>{
        for (final r in await db.fastingRecordDao.recordsOf(userId))
          r.attributionDate,
      };
      var hasGap = false;
      for (var i = 0; i < 30; i++) {
        if (!covered.contains(addDaysToIsoDate(today, -i))) {
          hasGap = true;
          break;
        }
      }
      if (hasGap) await _backfillRecentFastingRecords();
    } on Object {
      // 离线/未装配（测试/预览）：本地既有数据照常展示。
    }
  }

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
        // 归属校验（v1.13.27 修）：fetchActiveFast 物化/返回的是「当前窗口」
        // 记录，而本地刚关闭的可能是上一周期（前台对账补关闭）。归属日不一致
        // 时 recordId 与 endedAt 分属两个周期，上报会把当前 on_track 记录
        // 误判 broken（wcg 四连 broken 根因之一）；旧周期由服务端
        // autoCloseExpired ghost 兜底结算，跳过不丢数据。
        if (active.attributionDate.isNotEmpty &&
            active.attributionDate != record.date) {
          debugPrint(
            'StreakController: 归属日不一致跳过 F2 上报 '
            '(local=${record.date}, server=${active.attributionDate})',
          );
        } else {
          final requestId =
              _store.loadReportRequestId(record.date) ?? newClientRequestId();
          _store.saveReportRequestId(record.date, requestId);
          try {
            await report.reportEnd(
              clientRequestId: requestId,
              recordId: active.id,
              endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                record.endUtc * 1000,
                isUtc: true,
              ),
              // B2 窗口签名：本地周期计划锚点（plannedEnd = start + plannedSec）。
              plannedStartUtc: DateTime.fromMillisecondsSinceEpoch(
                record.startUtc * 1000,
                isUtc: true,
              ),
              plannedEndUtc: DateTime.fromMillisecondsSinceEpoch(
                (record.startUtc + record.plannedSec) * 1000,
                isUtc: true,
              ),
            );
            await _markRecordSynced(record);
          } on BusinessApiException catch (e) {
            if (e.code == 'FASTING_WINDOW_MISMATCH') {
              // 多端方案分叉（本机窗口 ≠ 服务端窗口）：触发一次方案下行
              // 收敛（v1.14.x：服务端方案即刻采纳替换本地）。闭环：本地
              // 记录保持 pending，/sync fastingRecord 通道按**自身锚点**
              // 上行，服务端同口径重算早退（拍板 C）——不丢、不重 broken。
              unawaited(ref.read(fastingPlanSyncProvider)?.pull());
            }
            // 其余业务拒绝（已结束/窗口外等）：本地记录保留，对账为准。
          }
        }
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
    unawaited(_backfillRecentFastingRecords());
  }

  /// 近 30 天断食历史下行回填 + 对账重传（v1.13.28：fastingRecord 无 /sync
  /// 通道，重装/换机后本地 drift 断食历史全丢，数据页趋势只剩本机新关闭的
  /// 记录——「打满当天才显示」根因；v1.14.x 数据页断食趋势扩到 30 天窗口，
  /// 回填范围对齐 14→30，服务端区间上限 62 天留余量）。只补缺：本机已有
  /// 关闭记录的归属日不动（本机为准）；on_track 进行中跳过（无结束锚点）；
  /// 回填行 syncStatus=synced、clientRequestId=`server-<id>`（与本地 UUID
  /// 幂等键不撞）。反向方向（本地 synced 但服务端查无 → 置回 pending 重传）
  /// 见函数内「对账重传」段。失败静默（离线保留本地既有展示，下轮对账再补）。
  Future<void> _backfillRecentFastingRecords() async {
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == 'anonymous') return; // 未登录无服务端历史可补
      AppDatabase? db;
      try {
        db = ref.read(appDatabaseProvider);
      } on Object {
        return; // 未注入数据库（测试/预览场景）：跳过回填
      }
      if (db == null) return;
      final today = _today();
      final from = addDaysToIsoDate(today, -29);
      final records = await ref
          .read(fastingReportApiProvider)
          .fetchRecentRecords(from: from, to: today);
      final existing = await db.fastingRecordDao.recordsOf(userId);
      // 对账重传（v1.14.x 拍板，堵「本地有、服务端没有」自愈盲区）：本地
      // 质态（非 on_track、非 deleted）且已标 synced 的记录，归属日落在拉取
      // 范围内但**服务端完整返回集**（含 on_track——进行中也算有，不算缺）
      // 无此归属日 → 该行从未真正上行（旧版本/异常路径误标 synced 后回填
      // 只下行补缺、永不再上行，wcg 09-23~28 丢数据根因）→ 置回 pending 并
      // 清空 serverId，既有 /sync push 通道下轮推上去。幂等：服务端
      // applyFastingRecordCreate 按归属日去重返回既有视图绝不覆盖
      // （v1.13.31），重复推无副作用；重标后行已非 synced，下轮对账不再动。
      // 与服务端 tombstone 不冲突：tombstone 下行（v1.13.32）只清本地
      // synced 行，而本机制只动「服务端查无」的行，两集合互斥。
      final serverDates = <String>{
        for (final r in records)
          if (r.attributionDate.isNotEmpty) r.attributionDate,
      };
      var reuploadCount = 0;
      for (final local in existing) {
        if (local.syncStatus != SyncStatus.synced) continue;
        if (local.deleted || local.result == 'on_track') continue;
        final date = local.attributionDate;
        if (date.compareTo(from) < 0 || date.compareTo(today) > 0) continue;
        if (serverDates.contains(date)) continue;
        await db.fastingRecordDao.resetForReupload(local.localId);
        reuploadCount++;
      }
      if (reuploadCount > 0) {
        debugPrint(
          'StreakController: 对账重传 $reuploadCount 天断食记录置回 pending'
          '（本地 synced 但服务端无此归属日）',
        );
        // 挂既有同步引擎触发一轮 push（不造新通道）；引擎未装配（测试/
        // 预览）时静默——启动/登录/前台等既有触发点下轮会推。
        try {
          unawaited(ref.read(recordSyncEngineProvider).syncNow());
        } on Object {
          // 未装配跳过。
        }
      }
      if (records.isEmpty) return;
      final existingDates = existing.map((r) => r.attributionDate).toSet();
      // 内容纠偏（2026-10-04 全量审计二轮，wcg「升级后趋势仍 0」实证）：
      // 本地**已同步**行与服务端同归属日终态记录内容不一致（actualSec/result/
      // qualified）时，以服务端为权威覆盖——不再依赖本地 createdAtUtc 可信
      // （吞周期 bug 时代/旧版本写入的 0 时长陈旧行 createdAtUtc 可能新于
      // 服务端 updatedAt，/sync 下行 LWW 覆盖永远不触发，陈旧行永久滞留）。
      // 仅动 synced 行：pending 行内容本机为准（上行 LWW 闭环拥有）。
      // 注：drift 行类型在本文件被 hide（与 domain FastingRecord 区分），
      // 用类型推断而非显式标注。
      final byDate = {for (final r in existing) r.attributionDate: r};
      var corrected = 0;
      for (final r in records) {
        if (r.result == 'on_track') continue;
        if (r.actualEndAt == null && r.result != 'makeup') continue;
        if (r.attributionDate.isEmpty) continue;
        final local = byDate[r.attributionDate];
        if (local == null || local.syncStatus != SyncStatus.synced) continue;
        final expectedResult = localResultNameOf(
          r.result,
          extendedMinutes: r.extendedMinutes,
        );
        final expectedSec = r.result == 'makeup'
            ? 0
            : r.fastedMinutes != null
            ? r.fastedMinutes! * 60
            : (r.actualEndAt ?? r.plannedEndAt)
                  .difference(r.actualStartAt ?? r.plannedStartAt)
                  .inSeconds;
        if (local.result == expectedResult &&
            local.actualSec == expectedSec &&
            local.qualified == r.isQualified) {
          continue; // 内容一致，不动（幂等稳定，不重复写）
        }
        await db.fastingRecordDao.upsertRecord(
          FastingRecordsCompanion(
            localId: Value(local.localId),
            userId: Value(userId),
            attributionDate: Value(r.attributionDate),
            startUtc: Value(
              (r.actualStartAt ?? r.plannedStartAt).millisecondsSinceEpoch ~/
                  1000,
            ),
            endUtc: Value(
              (r.actualEndAt ?? r.plannedEndAt).millisecondsSinceEpoch ~/ 1000,
            ),
            actualSec: Value(expectedSec),
            plannedSec: Value(
              r.plannedEndAt.difference(r.plannedStartAt).inSeconds,
            ),
            extendedMinutes: Value(r.extendedMinutes),
            result: Value(expectedResult),
            qualified: Value(r.isQualified),
            clientRequestId: Value(local.clientRequestId),
            syncStatus: const Value(SyncStatus.synced),
            // createdAtUtc 保留原值（drift 必填列）：本机行的本机写入时刻
            // 不伪造；后续 /sync 下行 LWW 会以服务端更新覆盖同内容（幂等无害）。
            createdAtUtc: Value(local.createdAtUtc),
          ),
        );
        corrected++;
      }
      if (corrected > 0) {
        debugPrint('StreakController: 断食记录内容纠偏 $corrected 天（以服务端为权威）');
      }
      // pending 活性收敛（审计）：F2 上行只在周期关闭当轮尝试一次，无重试
      // 通道——上行失败/未尝试（active==null）的本地记录 syncStatus 永久
      // 滞留 pending。服务端已有同归属日终态记录时（ghost 自动结算/他端
      // 上报），重试上行必吃 FASTING_ALREADY_ENDED，按「服务端终态为权威」
      // 回写 synced 收敛；内容本机为准不覆盖（见下），仅收敛同步标记。
      final serverTerminalDates = <String>{
        for (final r in records)
          if ((r.actualEndAt != null || r.result == 'makeup') &&
              r.result != 'on_track' &&
              r.attributionDate.isNotEmpty)
            r.attributionDate,
      };
      for (final local in existing) {
        if (local.syncStatus == SyncStatus.pending &&
            serverTerminalDates.contains(local.attributionDate)) {
          await db.fastingRecordDao.updateSyncStatus(
            local.localId,
            SyncStatus.synced,
          );
        }
      }
      for (final r in records) {
        // makeup 无 actualEndAt 但确为终态（同 /sync 下行放行口径）——
        // 此前守卫一并跳过，只走回填通道的设备补签日三态格显示「无记录」
        // 而服务端 streak 已计达标，同类自相矛盾。
        if (r.result == 'on_track') continue;
        if (r.actualEndAt == null && r.result != 'makeup') continue;
        if (r.attributionDate.isEmpty ||
            existingDates.contains(r.attributionDate)) {
          continue;
        }
        final start = r.actualStartAt ?? r.plannedStartAt;
        // 补签行无 actualEndAt：锚点回落计划终点（满足存储约束，时长=0）。
        final end = r.actualEndAt ?? r.plannedEndAt;
        await db.fastingRecordDao.upsertRecord(
          FastingRecordsCompanion(
            localId: Value('$userId-${r.attributionDate}'),
            userId: Value(userId),
            attributionDate: Value(r.attributionDate),
            startUtc: Value(start.millisecondsSinceEpoch ~/ 1000),
            endUtc: Value(end.millisecondsSinceEpoch ~/ 1000),
            actualSec: Value(
              // 与 /sync 下行同口径（全量口径审计 2026-10-04）：补签行
              // actualSec=0（补签计达标不计时长）；此前按 fastedMinutes
              // 落库且 result 塌缩为 completedOnTime，与 /sync 通道同记录
              // 两种本地形态，下游过滤全部失效。
              r.result == 'makeup'
                  ? 0
                  : r.fastedMinutes != null
                  ? r.fastedMinutes! * 60
                  : end.difference(start).inSeconds,
            ),
            plannedSec: Value(
              r.plannedEndAt.difference(r.plannedStartAt).inSeconds,
            ),
            extendedMinutes: Value(r.extendedMinutes),
            result: Value(
              localResultNameOf(r.result, extendedMinutes: r.extendedMinutes),
            ),
            qualified: Value(r.isQualified),
            clientRequestId: Value('server-${r.id}'),
            syncStatus: const Value(SyncStatus.synced),
            createdAtUtc: Value(DateTime.now().toUtc().toIso8601String()),
          ),
        );
      }
    } on Object {
      // 离线/未装配：本地既有数据照常展示。
    }
  }

  void _reconcile(ServerStreakView view, List<ServerMilestone> milestones) {
    // 服务端判分断签检测（v1.13.27）：服务端权威 streak 低于本地推演，且本地
    // 引擎没有未告知的断签弹窗（有则 D-12 弹窗已覆盖原因）——说明服务端把本地
    // 认为达标的周期判了不达标（如时区错配期的误判 broken），补一次带日期的
    // SnackBar 告知。判定必须在覆盖 _serverCurrentStreak 之前取本地推演值。
    final today = _today();
    final localProjected = _engine.currentStreak(today);
    String? noticeDate;
    if (view.currentStreak < localProjected) {
      final shownPopups = _store.loadShownBreakPopups();
      final hasLocalBreakExplanation = _engine.pendingMendDates.any(
        (d) => !shownPopups.contains(d),
      );
      if (!hasLocalBreakExplanation) {
        final candidate = _serverBreakNoticeDate(view, today);
        if (!_store.loadShownServerBreakNotices().contains(candidate)) {
          _store.markServerBreakNoticeShown(candidate);
          noticeDate = candidate;
        }
      }
    }
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
    state = _uiState(
      fromServer: true,
      // 里程碑徽章只庆祝「当下跨档」（档位 == 当前连胜，如他端今天刚
      // 达成）。重装/服务端历史重建后对账补录的历史档位（档位 < 当前
      // 连胜）静默标记不弹——否则首页「连续 10 天」横幅旁边会弹
      // 「连续 3 天」徽章，两个数字错位（2026-09-30 真机走查）。
      newMilestones: newly.where((d) => d == view.currentStreak).toList(),
      serverBreakNoticeDate: noticeDate,
    );
  }

  /// 服务端判分断签的告知日期：S1 不返回断签日〔假设〕，取「最后达标日的
  /// 次日」（须早于今天）；无法推导（lastQualifiedDate 缺失/次日即今天）
  /// 时退回昨天。
  String _serverBreakNoticeDate(ServerStreakView view, String today) {
    final lastQualified = view.lastQualifiedDate;
    if (lastQualified != null && lastQualified.isNotEmpty) {
      final next = addDaysToIsoDate(lastQualified, 1);
      if (next.compareTo(today) < 0) return next;
    }
    return addDaysToIsoDate(today, -1);
  }

  /// 服务端判分断签提示已展示（SnackBar 一次性消费；频控落库在检测时）。
  void consumeServerBreakNotice() {
    if (state.serverBreakNoticeDate != null) {
      state = _uiState(fromServer: state.fromServer);
    }
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
    String? serverBreakNoticeDate,
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
      serverBreakNoticeDate: serverBreakNoticeDate,
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

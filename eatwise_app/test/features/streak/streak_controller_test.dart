import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart' hide FastingRecord;
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/data/remote_fasting_record_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show recordSyncEngineProvider;
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';

/// streak 控制器：离线推演、服务端对账（S1 权威覆盖）、断食历史落 drift、
/// 补签卡在线/离线路径、断签弹窗频控。
void main() {
  const today = '2026-07-28';

  FastingRecord recordOf(String date, {bool qualified = true}) {
    return FastingRecord(
      date: date,
      startUtc: 1000,
      endUtc: 2000,
      actualSec: 1000,
      plannedSec: 960,
      extendedMinutes: 0,
      result: CycleResult.completedOnTime,
      qualified: qualified,
    );
  }

  group('离线推演与对账', () {
    late AppDatabase db;
    late InMemoryStreakLocalStore store;
    late _FakeStreakApi api;
    late _FakeFastingReportApi reportApi;

    setUp(() {
      db = AppDatabase.memory();
      store = InMemoryStreakLocalStore();
      api = _FakeStreakApi();
      reportApi = _FakeFastingReportApi();
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer container() {
      return ProviderContainer(
        overrides: <Override>[
          streakLocalStoreProvider.overrideWithValue(store),
          streakApiProvider.overrideWithValue(api),
          fastingReportApiProvider.overrideWithValue(reportApi),
          appDatabaseProvider.overrideWithValue(db),
          streakTodayProvider.overrideWithValue(() => today),
          currentUserIdProvider.overrideWithValue('u1'),
        ],
      );
    }

    test('离线：达标事件本地推演即时入账，fromServer=false；FastingRecord 落 drift', () async {
      api.offline = true;
      reportApi.offline = true;
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.onFastClosed(recordOf(today));
      final state = c.read(streakControllerProvider);
      expect(state.currentStreak, 1);
      expect(state.fromServer, isFalse);
      expect(state.status, StreakStatus.inStreak);

      // 断食历史落 drift（归属日 D-07 + D-08 达标标记，M6 趋势数据源）。
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows, hasLength(1));
      expect(rows.single.attributionDate, today);
      expect(rows.single.qualified, isTrue);

      // 同归属日重复关闭幂等（不重复 +1、不重复落库）。
      await controller.onFastClosed(recordOf(today));
      expect(c.read(streakControllerProvider).currentStreak, 1);
      expect(await db.fastingRecordDao.recordsOf('u1'), hasLength(1));
    });

    test('离线达标后恢复在线：S1 权威覆盖（冲突服从前端提示〔假设〕语义）', () async {
      api.offline = true;
      reportApi.offline = true;
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.onFastClosed(recordOf(today));
      expect(c.read(streakControllerProvider).currentStreak, 1);

      // 恢复在线：服务端权威值覆盖本地推演。
      api
        ..offline = false
        ..view = _view(currentStreak: 5, longestStreak: 9, stock: 1);
      await controller.refreshFromServer();
      final state = c.read(streakControllerProvider);
      expect(state.fromServer, isTrue);
      expect(state.currentStreak, 5);
      expect(state.longestStreak, 9);
      expect(state.mendCardBalance, 1);
    });

    test('对账补录历史里程碑（档位 < 当前连胜）静默标记不弹徽章', () async {
      // 重装/服务端历史重建后：S3 补录 3/7 档，但当前连胜已 10——
      // 弹「连续 3 天」徽章会与首页「连续 10 天」横幅错位（真机走查）。
      api
        ..view = _view(currentStreak: 10, longestStreak: 10, stock: 2)
        ..milestones = const <ServerMilestone>[
          ServerMilestone(days: 3, achievedAt: '2026-07-20T00:00:00Z'),
          ServerMilestone(days: 7, achievedAt: '2026-07-24T00:00:00Z'),
        ];
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.refreshFromServer();
      final state = c.read(streakControllerProvider);
      expect(state.currentStreak, 10);
      expect(state.justUnlockedMilestone, isNull);

      // 已静默标记入解锁集：下轮对账不会再当「新解锁」处理。
      await controller.refreshFromServer();
      expect(c.read(streakControllerProvider).justUnlockedMilestone, isNull);
    });

    test('对账发现当下跨档（档位 == 当前连胜，如他端今天达成）弹一次徽章', () async {
      api
        ..view = _view(currentStreak: 7, longestStreak: 7, stock: 2)
        ..milestones = const <ServerMilestone>[
          ServerMilestone(days: 3, achievedAt: '2026-07-24T00:00:00Z'),
          ServerMilestone(days: 7, achievedAt: '2026-07-28T00:00:00Z'),
        ];
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.refreshFromServer();
      // 7 档 == 当前连胜 → 弹；3 档是历史 → 静默。
      expect(c.read(streakControllerProvider).justUnlockedMilestone, 7);

      // 消费后不重复弹。
      controller.consumeMilestone();
      await controller.refreshFromServer();
      expect(c.read(streakControllerProvider).justUnlockedMilestone, isNull);
    });

    test('在线达标：F1 物化记录 → F2 幂等上行 → 拉 S1 对账', () async {
      api.view = _view(currentStreak: 3, longestStreak: 3, stock: 2);
      reportApi.active = const ServerActiveFast(
        id: 'rec-1',
        attributionDate: today,
      );
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.onFastClosed(recordOf(today));
      // 上行是 fire-and-forget，等事件循环排空。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(reportApi.endCalls, hasLength(1));
      expect(reportApi.endCalls.single.recordId, 'rec-1');
      // B2 窗口签名随行：本地周期计划锚点（start=1000, plannedSec=960）。
      expect(
        reportApi.endCalls.single.plannedStartUtc,
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000, isUtc: true),
      );
      expect(
        reportApi.endCalls.single.plannedEndUtc,
        DateTime.fromMillisecondsSinceEpoch((1000 + 960) * 1000, isUtc: true),
      );
      expect(api.fetchCount, greaterThanOrEqualTo(1));
      expect(c.read(streakControllerProvider).fromServer, isTrue);
      expect(c.read(streakControllerProvider).currentStreak, 3);

      // F2 上行成功后本地记录回写已同步。
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows.single.syncStatus, SyncStatus.synced);
    });

    test('归属日不一致：跳过 F2 上报（防误判 broken），本地结算不受影响', () async {
      // 前台对账补关闭的是上一周期（昨天），服务端物化的是当前窗口（今天）
      // ——recordId 与 endedAt 分属两个周期，上报会把当前记录误判 broken。
      api.view = _view(currentStreak: 1, longestStreak: 1, stock: 2);
      reportApi.active = const ServerActiveFast(
        id: 'rec-today',
        attributionDate: today,
      );
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.onFastClosed(recordOf('2026-07-27'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 不发 reportEnd；本地推演照常入账（乐观）。
      expect(reportApi.endCalls, isEmpty);
      expect(c.read(streakControllerProvider).currentStreak, 1);
      // 落库保留 pending（未上行标记），等后续同归属窗口或服务端 ghost 兜底。
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows, hasLength(1));
      expect(rows.single.attributionDate, '2026-07-27');
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('服务端判分断签：streak 骤降且本地无断签弹窗 → 带日期告知一次（频控不重复）', () async {
      // 本地推演 2 天连胜（07-26/27 达标、已结算到 07-27）；服务端权威 0
      // ——服务端把本地认为达标的周期判了不达标（时区错配期误判场景）。
      final engine = StreakEngine();
      engine.applyDayAchieved('2026-07-26', today: today);
      engine.applyDayAchieved('2026-07-27', today: today);
      engine.lastSettledDate = '2026-07-27';
      store.saveEngine(engine);
      api.view = _view(
        currentStreak: 0,
        longestStreak: 2,
        stock: 2,
        lastQualifiedDate: '2026-07-25',
      );
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      // build() 的 fire-and-forget 对账先排空。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 服务端权威覆盖 + 告知日 = 最后达标日次日（07-25 + 1）。
      var state = c.read(streakControllerProvider);
      expect(state.currentStreak, 0);
      expect(state.serverBreakNoticeDate, '2026-07-26');

      // 消费即清除；同一告知日落过频控，再次对账不再告知。
      controller.consumeServerBreakNotice();
      expect(c.read(streakControllerProvider).serverBreakNoticeDate, isNull);
      await controller.refreshFromServer();
      state = c.read(streakControllerProvider);
      expect(state.serverBreakNoticeDate, isNull);
      expect(state.currentStreak, 0);
    });

    test('服务端 streak 不低于本地推演 → 不告知', () async {
      final engine = StreakEngine();
      engine.applyDayAchieved('2026-07-27', today: today);
      engine.lastSettledDate = '2026-07-27';
      store.saveEngine(engine);
      api.view = _view(currentStreak: 1, longestStreak: 1, stock: 2);
      final c = container();
      addTearDown(c.dispose);
      c.read(streakControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.read(streakControllerProvider).serverBreakNoticeDate, isNull);
    });

    test('断食历史回填：补缺归属日落 drift（含服务端 broken 口径），进行中跳过', () async {
      // 重装/换机场景：本地 drift 断食历史全空，服务端有近 7 天记录。
      reportApi.recentRecords = <ServerFastingRecord>[
        ServerFastingRecord(
          id: 'r-completed',
          attributionDate: '2026-07-26',
          plannedStartAt: DateTime.parse('2026-07-25T12:00:00.000Z'),
          plannedEndAt: DateTime.parse('2026-07-26T04:00:00.000Z'),
          actualStartAt: DateTime.parse('2026-07-25T12:00:00.000Z'),
          actualEndAt: DateTime.parse('2026-07-26T04:00:00.000Z'),
          extendedMinutes: 0,
          result: 'completed',
          isQualified: true,
          fastedMinutes: 16 * 60,
        ),
        ServerFastingRecord(
          id: 'r-broken',
          attributionDate: '2026-07-27',
          plannedStartAt: DateTime.parse('2026-07-26T12:00:00.000Z'),
          plannedEndAt: DateTime.parse('2026-07-27T04:00:00.000Z'),
          actualStartAt: DateTime.parse('2026-07-26T12:00:00.000Z'),
          actualEndAt: DateTime.parse('2026-07-27T01:00:00.000Z'),
          extendedMinutes: 0,
          result: 'broken',
          isQualified: false,
          fastedMinutes: 13 * 60,
        ),
        ServerFastingRecord(
          id: 'r-ongoing',
          attributionDate: '2026-07-28',
          plannedStartAt: DateTime.parse('2026-07-27T12:00:00.000Z'),
          plannedEndAt: DateTime.parse('2026-07-28T04:00:00.000Z'),
          extendedMinutes: 0,
          result: 'on_track',
          isQualified: false,
        ),
      ];
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.refreshFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows, hasLength(2)); // on_track 无结束锚点，不回填
      final completed = rows.firstWhere(
        (r) => r.attributionDate == '2026-07-26',
      );
      expect(completed.qualified, isTrue);
      expect(completed.actualSec, 16 * 3600);
      expect(completed.syncStatus, SyncStatus.synced);
      expect(completed.clientRequestId, 'server-r-completed');
      final broken = rows.firstWhere((r) => r.attributionDate == '2026-07-27');
      expect(broken.qualified, isFalse);
      expect(broken.result, CycleResult.brokenEarly.name);
      expect(broken.actualSec, 13 * 3600);
    });

    test(
      '断食历史回填：补签（makeup）行落 result=makeup + actualSec=0（与 /sync 通道同口径）',
      () async {
        // 全量口径审计 2026-10-04：此前回填把 makeup 塌缩为 completedOnTime
        // 且按 fastedMinutes 落时长——与 /sync 下行同记录两种形态，补签的
        // 计划时长被当成真实断食成绩混进趋势/累计。
        reportApi.recentRecords = <ServerFastingRecord>[
          ServerFastingRecord(
            id: 'r-makeup',
            attributionDate: '2026-07-27',
            plannedStartAt: DateTime.parse('2026-07-26T11:00:00.000Z'),
            plannedEndAt: DateTime.parse('2026-07-27T01:00:00.000Z'),
            extendedMinutes: 0,
            result: 'makeup',
            isQualified: true,
            fastedMinutes: 14 * 60,
          ),
        ];
        final c = container();
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final rows = await db.fastingRecordDao.recordsOf('u1');
        final makeup = rows.firstWhere(
          (r) => r.attributionDate == '2026-07-27',
        );
        expect(makeup.result, CycleResult.makeup.name);
        expect(makeup.actualSec, 0);
        expect(makeup.qualified, isTrue); // 达标口径照常计入
      },
    );

    test('断食记录内容纠偏：已同步陈旧行以服务端为权威（createdAtUtc 新于服务端也纠）', () async {
      // wcg「升级后趋势仍 0」场景：bug 时代写入的 0 时长陈旧行（synced，
      // createdAtUtc 甚至比服务端 updatedAt 还新，/sync LWW 永不覆盖）。
      await db.fastingRecordDao.upsertRecord(
        FastingRecordsCompanion(
          localId: const Value('u1-2026-07-27'),
          userId: const Value('u1'),
          attributionDate: const Value('2026-07-27'),
          startUtc: const Value(0),
          endUtc: const Value(0),
          actualSec: const Value(0), // 陈旧错误值
          plannedSec: const Value(14 * 3600),
          extendedMinutes: const Value(0),
          result: Value(CycleResult.completedOnTime.name),
          qualified: const Value(false),
          clientRequestId: const Value('stale-row'),
          syncStatus: const Value(SyncStatus.synced),
          createdAtUtc: Value(
            DateTime.now().toUtc().toIso8601String(), // 新于服务端也照纠
          ),
        ),
      );
      reportApi.recentRecords = <ServerFastingRecord>[
        ServerFastingRecord(
          id: 'r-good',
          attributionDate: '2026-07-27',
          plannedStartAt: DateTime.parse('2026-07-26T11:00:00.000Z'),
          plannedEndAt: DateTime.parse('2026-07-27T01:00:00.000Z'),
          actualStartAt: DateTime.parse('2026-07-26T11:00:00.000Z'),
          actualEndAt: DateTime.parse('2026-07-27T01:00:00.000Z'),
          extendedMinutes: 0,
          result: 'completed',
          isQualified: true,
          fastedMinutes: 14 * 60,
        ),
      ];
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.refreshFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final row = (await db.fastingRecordDao.recordsOf(
        'u1',
      )).firstWhere((r) => r.attributionDate == '2026-07-27');
      expect(row.actualSec, 14 * 3600);
      expect(row.result, CycleResult.completedOnTime.name);
      expect(row.qualified, isTrue);
      expect(row.syncStatus, SyncStatus.synced);
      expect(row.clientRequestId, 'stale-row'); // 幂等键保留

      // 第二轮：内容已一致 → 不重复写（幂等稳定）。
      await controller.refreshFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final again = (await db.fastingRecordDao.recordsOf(
        'u1',
      )).firstWhere((r) => r.attributionDate == '2026-07-27');
      expect(again.actualSec, 14 * 3600);
    });

    test('断食历史回填：本机已有关闭记录的归属日不覆盖（本机为准）', () async {
      // 本机 07-27/07-25 周期已关闭落库（离线，F2 上行失败 → pending）。
      reportApi.offline = true;
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.onFastClosed(recordOf('2026-07-25'));
      await controller.onFastClosed(recordOf('2026-07-27'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 恢复在线：服务端 07-27 判了 broken（口径冲突），07-26 为缺口。
      reportApi
        ..offline = false
        ..recentRecords = <ServerFastingRecord>[
          ServerFastingRecord(
            id: 'r-broken',
            attributionDate: '2026-07-27',
            plannedStartAt: DateTime.parse('2026-07-26T12:00:00.000Z'),
            plannedEndAt: DateTime.parse('2026-07-27T04:00:00.000Z'),
            actualStartAt: DateTime.parse('2026-07-26T12:00:00.000Z'),
            actualEndAt: DateTime.parse('2026-07-27T01:00:00.000Z'),
            extendedMinutes: 0,
            result: 'broken',
            isQualified: false,
          ),
          ServerFastingRecord(
            id: 'r-completed',
            attributionDate: '2026-07-26',
            plannedStartAt: DateTime.parse('2026-07-25T12:00:00.000Z'),
            plannedEndAt: DateTime.parse('2026-07-26T04:00:00.000Z'),
            actualStartAt: DateTime.parse('2026-07-25T12:00:00.000Z'),
            actualEndAt: DateTime.parse('2026-07-26T04:00:00.000Z'),
            extendedMinutes: 0,
            result: 'completed',
            isQualified: true,
          ),
        ];
      await controller.refreshFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows, hasLength(3));
      // 本机行不被服务端口径覆盖（冲突由 S1 streak 权威口径另行收口）。
      final local = rows.firstWhere((r) => r.attributionDate == '2026-07-27');
      expect(local.qualified, isTrue);
      // 服务端已有 07-27 终态记录（broken）：F2 上行已无意义（重试必吃
      // FASTING_ALREADY_ENDED），pending 标记收敛为 synced（仅收敛标记，
      // 内容仍本机为准）。
      expect(local.syncStatus, SyncStatus.synced);
      // 服务端没有 07-25 记录的本地 pending 行保持 pending（上行仍待
      // 下轮 onFastClosed/对账窗口，不误标）。
      expect(
        rows.firstWhere((r) => r.attributionDate == '2026-07-25').syncStatus,
        SyncStatus.pending,
      );
      expect(
        rows.firstWhere((r) => r.attributionDate == '2026-07-26').syncStatus,
        SyncStatus.synced,
      );
    });

    test('断食历史回填：窗口对齐 30 天（数据页趋势 30 天档同源）', () async {
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.refreshFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(reportApi.recentCalls, isNotEmpty);
      // today = 2026-07-28，30 天窗口起点 = 2026-06-29（服务端上限 62 天留余量）。
      expect(reportApi.recentCalls.last.from, '2026-06-29');
      expect(reportApi.recentCalls.last.to, '2026-07-28');
    });

    test('数据页触发回填：30 天内有缺口补一次，二次触发不重复请求', () async {
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = reportApi.recentCalls.length; // build 启动回填已发过

      // 本地 drift 全空（30 天窗口必有缺口）→ 触发一次回填。
      await controller.ensureFastingHistoryBackfilled();
      expect(reportApi.recentCalls, hasLength(baseline + 1));
      expect(reportApi.recentCalls.last.from, '2026-06-29');

      // 每会话最多一次：再次触发不再发请求。
      await controller.ensureFastingHistoryBackfilled();
      expect(reportApi.recentCalls, hasLength(baseline + 1));
    });

    test('数据页触发回填：本地 30 天无缺口 → 不发请求', () async {
      // 预先落满 30 天本地记录（2026-06-29 ~ 2026-07-28）。
      for (var i = 0; i < 30; i++) {
        final date = addDaysToIsoDate(today, -i);
        await db.fastingRecordDao.upsertRecord(
          FastingRecordsCompanion(
            localId: Value('u1-$date'),
            userId: const Value('u1'),
            attributionDate: Value(date),
            startUtc: const Value(1000),
            endUtc: const Value(2000),
            actualSec: const Value(16 * 3600),
            plannedSec: const Value(16 * 3600),
            extendedMinutes: const Value(0),
            result: Value(CycleResult.completedOnTime.name),
            qualified: const Value(true),
            clientRequestId: Value('req-$date'),
            syncStatus: const Value(SyncStatus.synced),
            createdAtUtc: Value(DateTime.now().toUtc().toIso8601String()),
          ),
        );
      }
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = reportApi.recentCalls.length;

      await controller.ensureFastingHistoryBackfilled();
      expect(reportApi.recentCalls, hasLength(baseline)); // 无缺口零请求
    });

    test('数据页触发回填：未登录（anonymous）不发请求', () async {
      final c = ProviderContainer(
        overrides: <Override>[
          streakLocalStoreProvider.overrideWithValue(store),
          streakApiProvider.overrideWithValue(api),
          fastingReportApiProvider.overrideWithValue(reportApi),
          appDatabaseProvider.overrideWithValue(db),
          streakTodayProvider.overrideWithValue(() => today),
          currentUserIdProvider.overrideWithValue('anonymous'),
        ],
      );
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = reportApi.recentCalls.length;

      await controller.ensureFastingHistoryBackfilled();
      expect(reportApi.recentCalls, hasLength(baseline));
    });

    group('对账重传（本地 synced 但服务端无此归属日）', () {
      /// 直接落一条本地 drift 断食行（模拟旧版本/异常路径误标 synced）。
      Future<void> seedDriftRow(
        String date, {
        SyncStatus status = SyncStatus.synced,
        String? serverId,
        String result = 'completedOnTime',
        bool deleted = false,
        String userId = 'u1',
      }) {
        return db.fastingRecordDao.upsertRecord(
          FastingRecordsCompanion(
            localId: Value('$userId-$date'),
            userId: Value(userId),
            attributionDate: Value(date),
            startUtc: const Value(1000),
            endUtc: const Value(1000 + 16 * 3600),
            actualSec: const Value(16 * 3600),
            plannedSec: const Value(16 * 3600),
            extendedMinutes: const Value(0),
            result: Value(result),
            qualified: const Value(true),
            clientRequestId: Value('req-$date'),
            syncStatus: Value(status),
            serverId: Value(serverId),
            deleted: Value(deleted),
            createdAtUtc: const Value('2026-07-01T00:00:00.000Z'),
          ),
        );
      }

      ServerFastingRecord serverRecord(
        String date, {
        String result = 'completed',
        bool withEnd = true,
      }) {
        return ServerFastingRecord(
          id: 'srv-$date',
          attributionDate: date,
          plannedStartAt: DateTime.parse('2026-07-01T12:00:00.000Z'),
          plannedEndAt: DateTime.parse('2026-07-02T04:00:00.000Z'),
          actualStartAt: DateTime.parse('2026-07-01T12:00:00.000Z'),
          actualEndAt: withEnd
              ? DateTime.parse('2026-07-02T04:00:00.000Z')
              : null,
          extendedMinutes: 0,
          result: result,
          isQualified: result != 'broken',
        );
      }

      test('重标触发：服务端无 → pending + 清 serverId；服务端有/pending/范围外不动', () async {
        reportApi.recentRecords = <ServerFastingRecord>[
          serverRecord('2026-07-26'),
        ];
        await seedDriftRow('2026-07-26', serverId: 'srv-a'); // 服务端有 → 不动
        await seedDriftRow('2026-07-27', serverId: 'srv-b'); // 服务端无 → 重标
        await seedDriftRow('2026-07-25', status: SyncStatus.pending); // 不动
        await seedDriftRow('2026-06-01', serverId: 'srv-old'); // 范围外 → 不动
        // 不装配 recordSyncEngineProvider（sharedPreferencesProvider 未注入
        // 必抛）：push 触发被静默吞下，验证重标本体。
        final c = container();
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final reupload = (await db.fastingRecordDao.getByLocalId(
          'u1-2026-07-27',
        ))!;
        expect(reupload.syncStatus, SyncStatus.pending);
        expect(reupload.serverId, isNull);
        final kept = (await db.fastingRecordDao.getByLocalId('u1-2026-07-26'))!;
        expect(kept.syncStatus, SyncStatus.synced);
        expect(kept.serverId, 'srv-a');
        expect(
          (await db.fastingRecordDao.getByLocalId('u1-2026-07-25'))!.syncStatus,
          SyncStatus.pending,
        );
        final outOfRange = (await db.fastingRecordDao.getByLocalId(
          'u1-2026-06-01',
        ))!;
        expect(outOfRange.syncStatus, SyncStatus.synced);
        expect(outOfRange.serverId, 'srv-old');
      });

      test('服务端同归属日为 on_track（进行中）也算有 → 不重标', () async {
        reportApi.recentRecords = <ServerFastingRecord>[
          serverRecord('2026-07-27', result: 'on_track', withEnd: false),
        ];
        await seedDriftRow('2026-07-27', serverId: 'srv-b');
        final c = container();
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final row = (await db.fastingRecordDao.getByLocalId('u1-2026-07-27'))!;
        expect(row.syncStatus, SyncStatus.synced);
        expect(row.serverId, 'srv-b');
      });

      test('本地 on_track 行与 deleted 行不重标', () async {
        reportApi.recentRecords = const <ServerFastingRecord>[]; // 服务端全空
        await seedDriftRow('2026-07-27', serverId: 'srv-x', result: 'on_track');
        await seedDriftRow('2026-07-26', serverId: 'srv-y', deleted: true);
        final c = container();
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final onTrack = (await db.fastingRecordDao.getByLocalId(
          'u1-2026-07-27',
        ))!;
        expect(onTrack.syncStatus, SyncStatus.synced);
        expect(onTrack.serverId, 'srv-x');
        final tombstone = (await db.fastingRecordDao.getByLocalId(
          'u1-2026-07-26',
        ))!;
        expect(tombstone.syncStatus, SyncStatus.synced);
        expect(tombstone.serverId, 'srv-y');
      });

      test('匿名（anonymous）不回填不重标', () async {
        await seedDriftRow(
          '2026-07-27',
          serverId: 'srv-b',
          userId: 'anonymous',
        );
        final c = ProviderContainer(
          overrides: <Override>[
            streakLocalStoreProvider.overrideWithValue(store),
            streakApiProvider.overrideWithValue(api),
            fastingReportApiProvider.overrideWithValue(reportApi),
            appDatabaseProvider.overrideWithValue(db),
            streakTodayProvider.overrideWithValue(() => today),
            currentUserIdProvider.overrideWithValue('anonymous'),
          ],
        );
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final row = (await db.fastingRecordDao.getByLocalId(
          'anonymous-2026-07-27',
        ))!;
        expect(row.syncStatus, SyncStatus.synced);
        expect(row.serverId, 'srv-b');
      });

      test('幂等：重标后二次对账不再动（保持 pending 等待上行）', () async {
        reportApi.recentRecords = const <ServerFastingRecord>[];
        await seedDriftRow('2026-07-27', serverId: 'srv-b');
        final c = container();
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // 二次对账：行已非 synced，不再触碰。
        await controller.refreshFromServer();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final row = (await db.fastingRecordDao.getByLocalId('u1-2026-07-27'))!;
        expect(row.syncStatus, SyncStatus.pending);
        expect(row.serverId, isNull);
      });

      test('重标后触发一轮 push：/sync push 上行并回填新 serverId（端到端）', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final adapter = FakeHttpAdapter();
        final dio = createApiDio(config: ApiConfig());
        dio.httpClientAdapter = adapter;
        adapter.stub(
          '/sync/push',
          StubResponse.json(
            200,
            StubResponse.envelope(<String, dynamic>{
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'clientRequestId': 'req-2026-07-27',
                  'status': 'applied',
                  'serverEntry': <String, dynamic>{
                    'id': 'srv-new',
                    'version': 1,
                  },
                },
              ],
              'syncToken': 'st_x',
            }),
          ),
        );
        final repo = RecordRepository(
          db: db,
          remote: FakeRecordRemote(),
          location: tz.UTC,
          userId: 'u1',
        );
        addTearDown(repo.dispose);
        final engine = RecordSyncEngine(
          repository: repo,
          prefs: prefs,
          fastingRecordSync: RemoteFastingRecordSync(dio: dio),
        );
        reportApi.recentRecords = const <ServerFastingRecord>[]; // 服务端全空
        await seedDriftRow('2026-07-27', serverId: 'srv-old');
        final c = ProviderContainer(
          overrides: <Override>[
            streakLocalStoreProvider.overrideWithValue(store),
            streakApiProvider.overrideWithValue(api),
            fastingReportApiProvider.overrideWithValue(reportApi),
            appDatabaseProvider.overrideWithValue(db),
            streakTodayProvider.overrideWithValue(() => today),
            currentUserIdProvider.overrideWithValue('u1'),
            recordSyncEngineProvider.overrideWithValue(engine),
          ],
        );
        addTearDown(c.dispose);
        final controller = c.read(streakControllerProvider.notifier);
        await controller.refreshFromServer();
        // drift 查询走后台 isolate，重标→syncNow→push 链给足排空时间；
        // build 启动对账 + 显式对账并发时可能各触发一轮 push（幂等无害）。
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // 重标触发了 /sync push，载荷为该行 create op。
        expect(adapter.requestBodies, isNotEmpty);
        final body = adapter.requestBodies.first as Map<dynamic, dynamic>;
        final op =
            (body['ops']! as List<dynamic>).single as Map<dynamic, dynamic>;
        expect(op['entity'], 'fastingRecord');
        expect(op['op'], 'create');
        expect(
          (op['payload']! as Map<dynamic, dynamic>)['attributionDate'],
          '2026-07-27',
        );
        // 上行成功回填：synced + 新 serverId（幂等键复用原 clientRequestId）。
        final row = (await db.fastingRecordDao.getByLocalId('u1-2026-07-27'))!;
        expect(row.syncStatus, SyncStatus.synced);
        expect(row.serverId, 'srv-new');
      });
    });

    test('F2 窗口签名不一致（FASTING_WINDOW_MISMATCH）：触发方案下行收敛，记录保持 pending', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final planSync = _RecordingPlanSync(prefs);
      reportApi
        ..active = const ServerActiveFast(id: 'rec-1', attributionDate: today)
        ..endError = const BusinessApiException(
          httpStatus: 409,
          code: 'FASTING_WINDOW_MISMATCH',
          message: 'mismatch',
        );
      final c = ProviderContainer(
        overrides: <Override>[
          streakLocalStoreProvider.overrideWithValue(store),
          streakApiProvider.overrideWithValue(api),
          fastingReportApiProvider.overrideWithValue(reportApi),
          appDatabaseProvider.overrideWithValue(db),
          streakTodayProvider.overrideWithValue(() => today),
          currentUserIdProvider.overrideWithValue('u1'),
          fastingPlanSyncProvider.overrideWithValue(planSync),
        ],
      );
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      await controller.onFastClosed(recordOf(today));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 上行被拒 → 触发一次方案下行收敛（多端分叉自愈）；本地记录保持
      // pending 等下轮窗口对齐后再上报。
      expect(planSync.pullCalls, 1);
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('补签卡在线（S2）：服务端视图对账，本地账本同步', () async {
      // 预播种：07-25/26 已达标并结算到 07-26；build 启动结算 → 07-27 断签。
      store.saveEngine(_preseededEngine());
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      expect(controller.state.pendingMendDates, contains('2026-07-27'));

      api.view = _view(currentStreak: 3, longestStreak: 3, stock: 1);
      final result = await controller.useMendCard('2026-07-27');
      expect(api.mendCalls, hasLength(1));
      expect(result.restoredStreak, 3);
      expect(result.cardsLeft, 1);
      expect(controller.state.fromServer, isTrue);
      expect(controller.state.mendCardBalance, 1);
    });

    test('补签卡离线：本地推演先行，fromServer=false', () async {
      api.offline = true;
      store.saveEngine(_preseededEngine());
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);

      final result = await controller.useMendCard('2026-07-27');
      expect(api.mendCalls, hasLength(1)); // 尝试过在线
      expect(result.restoredStreak, 3); // 25+26+27(m) 连续
      expect(controller.state.fromServer, isFalse);
      expect(controller.state.status, StreakStatus.inStreak);
    });

    test('断签弹窗频控：同一断签日只自动弹 1 次', () async {
      api.offline = true;
      reportApi.offline = true;
      store.saveEngine(_preseededEngine());
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      // build 启动补结算即置弹窗标记（下次进入前台弹出）。
      expect(controller.state.pendingBreakPopupDate, '2026-07-27');

      controller.markBreakPopupShown('2026-07-27');
      expect(controller.state.pendingBreakPopupDate, isNull);

      // 再次结算不重复置弹窗标记。
      controller.settleIfNeeded();
      expect(controller.state.pendingBreakPopupDate, isNull);
    });

    test('不达标记录：仅落库不进 streak（T10，次日结算归零）', () async {
      api.offline = true;
      reportApi.offline = true;
      final c = container();
      addTearDown(c.dispose);
      final controller = c.read(streakControllerProvider.notifier);
      await controller.onFastClosed(recordOf(today, qualified: false));
      expect(c.read(streakControllerProvider).currentStreak, 0);
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows, hasLength(1));
      expect(rows.single.qualified, isFalse);

      // 同日重新达标（容差内手动结束）：streak 入账且落库幂等。
      await controller.onFastClosed(recordOf(today));
      expect(c.read(streakControllerProvider).currentStreak, 1);
      expect(await db.fastingRecordDao.recordsOf('u1'), hasLength(1));
    });
  });

  group('SharedPreferences 本地存储', () {
    test('引擎快照 + 弹窗频控 + 幂等键往返', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesStreakLocalStore(prefs);

      final engine = StreakEngine();
      engine.applyDayAchieved(today, today: today);
      store.saveEngine(engine);
      expect(store.loadEngine()?.qualifiedDates, contains(today));

      expect(store.loadShownBreakPopups(), isEmpty);
      store.markBreakPopupShown('2026-07-27');
      expect(store.loadShownBreakPopups(), contains('2026-07-27'));

      expect(store.loadReportRequestId(today), isNull);
      store.saveReportRequestId(today, 'req-1');
      expect(store.loadReportRequestId(today), 'req-1');
    });
  });
}

/// 预播种引擎：07-25/26 已达标、结算到 07-26（build 启动结算 → 07-27 断签）。
StreakEngine _preseededEngine() {
  final engine = StreakEngine();
  engine.applyDayAchieved('2026-07-25', today: '2026-07-28');
  engine.applyDayAchieved('2026-07-26', today: '2026-07-28');
  engine.lastSettledDate = '2026-07-26';
  engine.mendCardMonth = '2026-07';
  return engine;
}

ServerStreakView _view({
  required int currentStreak,
  required int longestStreak,
  required int stock,
  String? lastQualifiedDate,
}) {
  return ServerStreakView(
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    lastQualifiedDate: lastQualifiedDate,
    mendCardStock: stock,
    mendCardGrantsThisMonth: 2,
    mendCardExpiresAt: '2026-07-31',
    mendCardUsableWindowDays: 7,
    mendCardStatus: stock > 0 ? 'available' : 'empty',
  );
}

/// 可切换在线/离线的 S1/S2/S3 桩。
final class _FakeStreakApi extends StreakApi {
  _FakeStreakApi() : super(Dio());

  bool offline = false;
  ServerStreakView? view;
  int fetchCount = 0;
  final List<String> mendCalls = <String>[];

  /// S3 里程碑桩（默认空集）。
  List<ServerMilestone> milestones = const <ServerMilestone>[];

  @override
  Future<ServerStreakView> fetchStreak() async {
    fetchCount++;
    if (offline) throw const NetworkApiException();
    return view ?? _view(currentStreak: 0, longestStreak: 0, stock: 2);
  }

  @override
  Future<ServerStreakView> useMendCard({
    required String clientRequestId,
    required String date,
  }) async {
    mendCalls.add(date);
    if (offline) throw const NetworkApiException();
    return view ?? _view(currentStreak: 0, longestStreak: 0, stock: 1);
  }

  @override
  Future<List<ServerMilestone>> fetchMilestones() async {
    if (offline) throw const NetworkApiException();
    return milestones;
  }
}

/// F1/F2 上行桩。
final class _FakeFastingReportApi extends FastingReportApi {
  _FakeFastingReportApi() : super(Dio());

  bool offline = false;
  ServerActiveFast? active;
  List<ServerFastingRecord> recentRecords = const <ServerFastingRecord>[];

  /// fetchRecentRecords 调用参数留痕（回填窗口断言用）。
  final List<({String from, String to})> recentCalls =
      <({String from, String to})>[];

  /// 非 null 时 reportEnd 抛该异常（如 FASTING_WINDOW_MISMATCH 业务码）。
  Object? endError;
  final List<
    ({
      String recordId,
      String clientRequestId,
      DateTime? plannedStartUtc,
      DateTime? plannedEndUtc,
    })
  >
  endCalls =
      <
        ({
          String recordId,
          String clientRequestId,
          DateTime? plannedStartUtc,
          DateTime? plannedEndUtc,
        })
      >[];

  @override
  Future<ServerActiveFast?> fetchActiveFast() async {
    if (offline) throw const NetworkApiException();
    return active;
  }

  @override
  Future<void> reportEnd({
    required String clientRequestId,
    required String recordId,
    required DateTime endedAtUtc,
    DateTime? plannedStartUtc,
    DateTime? plannedEndUtc,
  }) async {
    if (offline) throw const NetworkApiException();
    endCalls.add((
      recordId: recordId,
      clientRequestId: clientRequestId,
      plannedStartUtc: plannedStartUtc,
      plannedEndUtc: plannedEndUtc,
    ));
    final e = endError;
    if (e != null) throw e;
    // 与生产一致：F2 上行成功后服务端即存在该归属日终态记录，后续
    // GET /fasting/records 会返回它（对账重传据此判定「服务端有」）。
    final a = active;
    if (a != null &&
        a.id == recordId &&
        a.attributionDate.isNotEmpty &&
        !recentRecords.any((r) => r.attributionDate == a.attributionDate)) {
      recentRecords = <ServerFastingRecord>[
        ...recentRecords,
        ServerFastingRecord(
          id: a.id,
          attributionDate: a.attributionDate,
          plannedStartAt:
              plannedStartUtc ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          plannedEndAt:
              plannedEndUtc ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          actualStartAt: plannedStartUtc,
          actualEndAt: endedAtUtc,
          extendedMinutes: 0,
          result: 'completed',
          isQualified: true,
        ),
      ];
    }
  }

  @override
  Future<List<ServerFastingRecord>> fetchRecentRecords({
    required String from,
    required String to,
  }) async {
    if (offline) throw const NetworkApiException();
    recentCalls.add((from: from, to: to));
    return recentRecords;
  }
}

/// 方案下行收敛计数桩（F2 窗口签名不一致触发自愈用例）。
final class _RecordingPlanSync extends FastingPlanSync {
  _RecordingPlanSync(SharedPreferences prefs)
    : super(api: FastingPlanApi(Dio()), prefs: prefs, userId: () => 'u1');

  int pullCalls = 0;

  @override
  Future<void> pull() async {
    pullCalls++;
  }
}

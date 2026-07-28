import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart' hide FastingRecord;
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(api.fetchCount, greaterThanOrEqualTo(1));
      expect(c.read(streakControllerProvider).fromServer, isTrue);
      expect(c.read(streakControllerProvider).currentStreak, 3);

      // F2 上行成功后本地记录回写已同步。
      final rows = await db.fastingRecordDao.recordsOf('u1');
      expect(rows.single.syncStatus, SyncStatus.synced);
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
}) {
  return ServerStreakView(
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    lastQualifiedDate: null,
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
    return const <ServerMilestone>[];
  }
}

/// F1/F2 上行桩。
final class _FakeFastingReportApi extends FastingReportApi {
  _FakeFastingReportApi() : super(Dio());

  bool offline = false;
  ServerActiveFast? active;
  final List<({String recordId, String clientRequestId})> endCalls =
      <({String recordId, String clientRequestId})>[];

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
  }) async {
    if (offline) throw const NetworkApiException();
    endCalls.add((recordId: recordId, clientRequestId: clientRequestId));
  }
}

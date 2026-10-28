import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// M3 记录仓库单测：四态迁移（T1–T9）、D-11 撤销窗边界、离线 pending、
/// 失败回滚、双语搜索、聚合重算（《规格-数据同步与四态持久化》§1.3/§6）。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late tz.Location location;

  RecordDraft draft({double amountG = 100, String foodId = 'f-rice'}) {
    return RecordDraft(
      foodId: foodId,
      amountG: amountG,
      mealUtc: DateTime.utc(2026, 7, 28, 4), // 上海时间 12:00，归属 2026-07-28
      source: EntrySource.manual,
    );
  }

  RecordRepository repo({
    Duration undoWindow = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) {
    return RecordRepository(
      db: db,
      remote: remote,
      location: location,
      undoWindow: undoWindow,
      clock: clock,
    );
  }

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    location = tz.getLocation('Asia/Shanghai');
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'live location changes new attribution without dropping the undo window',
    () async {
      final repository = RecordRepository(
        db: db,
        remote: remote,
        location: location,
        locationResolver: () => location,
      );
      addTearDown(repository.dispose);
      final first = await repository.addEntry(draft());
      location = tz.getLocation('America/New_York');
      final second = await repository.addEntry(draft());
      expect(first.localDate, '2026-07-28');
      expect(second.localDate, '2026-07-28');
      // UTC 04:00 is midnight in New York; use a timestamp on the prior date.
      final prior = await repository.addEntry(
        RecordDraft(
          foodId: 'f-rice',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 7, 28, 1),
          source: EntrySource.manual,
        ),
      );
      expect(prior.localDate, '2026-07-27');
      expect(repository.location.name, 'America/New_York');
      await repository.undo(first.localId);
      expect(await db.foodEntryDao.getByLocalId(first.localId), isNull);
    },
  );

  group('四态迁移', () {
    test('T1+T4 在线确认 → submitting，撤销窗结束自动上行 → synced 回填', () async {
      final repository = repo(undoWindow: const Duration(milliseconds: 30));
      final entry = await repository.addEntry(draft());
      expect(entry.syncStatus, SyncStatus.submitting);
      expect(entry.serverId, isNull);
      expect(entry.clientRequestId, isNotEmpty);
      expect(remote.pushCount, 0, reason: '撤销窗内不发上行请求（§1.3 T1 假设）');

      await Future<void>.delayed(const Duration(milliseconds: 120));
      final after = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(after!.syncStatus, SyncStatus.synced);
      expect(after.serverId, isNotNull);
      expect(after.serverVersion, isNotNull);
      expect(after.serverUpdatedAt, isNotNull);
      expect(after.retryCount, 0);
      await repository.dispose();
    });

    test('T2 离线确认 → 立即 pending，计入待同步计数', () async {
      remote.mode = FakeRemoteMode.offline;
      final repository = repo();
      final countFuture = repository.watchPendingCount().firstWhere(
        (c) => c == 1,
      );
      final entry = await repository.addEntry(draft());
      expect(entry.syncStatus, SyncStatus.pending);
      expect(await countFuture, 1);
      await repository.dispose();
    });

    test('T5 可重试失败 → pending + retryCount+1；T8 恢复后重试 → synced', () async {
      remote.mode = FakeRemoteMode.retryableFailure;
      final repository = repo();
      final entry = await repository.addEntry(draft());
      await repository.flushEntry(entry.localId);

      var after = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(after!.syncStatus, SyncStatus.pending);
      expect(after.retryCount, 1);
      expect(after.lastError, 'NETWORK_ERROR');

      remote.mode = FakeRemoteMode.success;
      final attempted = await repository.retryPending();
      expect(attempted, 1);
      after = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(after!.syncStatus, SyncStatus.synced);
      expect(after.serverId, isNotNull);
      await repository.dispose();
    });

    test('T6 409 版本冲突 → conflicted，计入待同步入口', () async {
      remote.mode = FakeRemoteMode.conflict;
      final repository = repo();
      final entry = await repository.addEntry(draft());
      await repository.flushEntry(entry.localId);

      final after = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(after!.syncStatus, SyncStatus.conflicted);
      expect(after.lastError, 'VERSION_CONFLICT');
      expect(await repository.watchPendingCount().first, 1);
      await repository.dispose();
    });

    test('T7 4xx 校验拒绝 → 回滚删除 + 失败事件，不再重试', () async {
      remote.mode = FakeRemoteMode.reject;
      final repository = repo();
      final failureFuture = repository.failures.first;
      final entry = await repository.addEntry(draft());
      await repository.flushEntry(entry.localId);

      expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);
      final failure = await failureFuture;
      expect(failure.localId, entry.localId);
      expect(failure.code, 'VALIDATION_FAILED');
      // 聚合同步回滚（当日无有效记录）。
      final daily = await db.foodEntryDao.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      );
      expect(daily!.entryCount, 0);
      await repository.dispose();
    });

    test(
      'T9 synced 后编辑 → submitting + 新 clientRequestId + localVersion+1',
      () async {
        final repository = repo(undoWindow: const Duration(milliseconds: 30));
        final entry = await repository.addEntry(draft());
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final synced = await db.foodEntryDao.getByLocalId(entry.localId);
        expect(synced!.syncStatus, SyncStatus.synced);

        final updated = await repository.updateEntry(
          entry.localId,
          amountG: 200,
        );
        expect(updated.syncStatus, SyncStatus.submitting);
        expect(updated.localVersion, synced.localVersion + 1);
        expect(updated.clientRequestId, isNot(synced.clientRequestId));
        await repository.dispose();
      },
    );
  });

  group('D-11 撤销窗', () {
    test('T3 撤销窗内撤销 → 本地删除、远程零请求、聚合回滚', () async {
      final repository = repo();
      final entry = await repository.addEntry(draft());
      expect(await repository.undo(entry.localId), isTrue);
      expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);
      expect(remote.pushCount, 0);
      final daily = await db.foodEntryDao.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      );
      expect(daily!.entryCount, 0);
      await repository.dispose();
    });

    test('边界：到期时刻不可撤销，到期前 1ms 可撤销', () async {
      var now = DateTime.utc(2026, 7, 28, 4);
      final repository = repo(clock: () => now);
      final expired = await repository.addEntry(draft());
      now = now.add(const Duration(seconds: 10)); // 恰好到期
      expect(await repository.undo(expired.localId), isFalse);
      expect(await db.foodEntryDao.getByLocalId(expired.localId), isNotNull);

      final alive = await repository.addEntry(draft(foodId: 'f-egg'));
      now = now.add(
        const Duration(seconds: 10) - const Duration(milliseconds: 1),
      );
      expect(await repository.undo(alive.localId), isTrue);
      await repository.dispose();
    });

    test('T2 离线写入在撤销窗内同样可撤销（纯本地回滚）', () async {
      remote.mode = FakeRemoteMode.offline;
      final repository = repo();
      final entry = await repository.addEntry(draft());
      expect(entry.syncStatus, SyncStatus.pending);
      expect(await repository.undo(entry.localId), isTrue);
      expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);
      await repository.dispose();
    });
  });

  group('双语搜索（D-15/D-16）', () {
    test('中文名 / 中文别名匹配', () async {
      final repository = repo();
      expect((await repository.searchFoods('白米饭')).single.id, 'f-rice');
      expect((await repository.searchFoods('米饭')).single.id, 'f-rice');
      expect((await repository.searchFoods('水煮蛋')).single.id, 'f-egg');
      await repository.dispose();
    });

    test('英文名 / 英文别名匹配（大小写不敏感）', () async {
      final repository = repo();
      expect((await repository.searchFoods('White')).single.id, 'f-rice');
      expect((await repository.searchFoods('RICE')).single.id, 'f-rice');
      expect((await repository.searchFoods('chicken')).single.id, 'f-chicken');
      await repository.dispose();
    });

    test('无匹配 → 空列表', () async {
      final repository = repo();
      expect(await repository.searchFoods('不存在的食物'), isEmpty);
      await repository.dispose();
    });
  });

  group('聚合重算', () {
    test('入账按份量换算快照并累加当日聚合', () async {
      final repository = repo();
      final entry = await repository.addEntry(draft(amountG: 150));
      expect(entry.kcal, closeTo(174, 0.01)); // 116 × 1.5
      final daily = await db.foodEntryDao.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      );
      expect(daily!.entryCount, 1);
      expect(daily.kcal, closeTo(174, 0.01));
      expect(daily.isLocalEstimate, isTrue);
      await repository.dispose();
    });

    test('份量修改实时重算快照与当日聚合', () async {
      final repository = repo();
      final entry = await repository.addEntry(draft());
      final updated = await repository.updateEntry(entry.localId, amountG: 200);
      expect(updated.amountG, 200);
      expect(updated.kcal, closeTo(232, 0.01));
      expect(updated.carbG, closeTo(51.8, 0.01));
      final daily = await db.foodEntryDao.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      );
      expect(daily!.kcal, closeTo(232, 0.01));
      expect(daily.entryCount, 1);
      await repository.dispose();
    });

    test('份量边界与服务端一致：非法值不得写入或改坏现有记录', () async {
      final repository = repo();
      addTearDown(repository.dispose);
      final original = await repository.addEntry(draft());
      for (final amount in [
        double.nan,
        double.infinity,
        -double.infinity,
        0.01,
        5001.0,
      ]) {
        await expectLater(
          repository.addEntry(draft(amountG: amount)),
          throwsArgumentError,
        );
        await expectLater(
          repository.updateEntry(original.localId, amountG: amount),
          throwsArgumentError,
        );
      }
      final entries = await repository.entriesForDate(draft().mealUtc);
      expect(entries, hasLength(1));
      expect(entries.single.amountG, 100);
      for (final amount in [0.1, 5000.0]) {
        expect(
          (await repository.addEntry(draft(amountG: amount))).amountG,
          amount,
        );
      }
    });

    test('多条记录聚合求和；非法份量/未知食物拒绝入账', () async {
      final repository = repo();
      await repository.addEntry(draft());
      await repository.addEntry(draft(foodId: 'f-egg')); // 144 kcal
      final daily = await db.foodEntryDao.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      );
      expect(daily!.entryCount, 2);
      expect(daily.kcal, closeTo(260, 0.01));

      await expectLater(
        repository.addEntry(draft(amountG: 0)),
        throwsArgumentError,
      );
      await expectLater(
        repository.addEntry(draft(foodId: 'f-unknown')),
        throwsArgumentError,
      );
      await repository.dispose();
    });
  });

  group('餐次（薄荷走查优化点 2，纯本地属性）', () {
    test('显式选择餐次入账落库；缺省按就餐时间本地小时智能预判', () async {
      final repository = repo();
      // 显式选择 snack（哪怕就餐时间在中午）。
      final chosen = await repository.addEntry(
        RecordDraft(
          foodId: 'f-rice',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 7, 28, 4), // 上海 12:00
          source: EntrySource.manual,
          mealType: MealType.snack,
        ),
      );
      expect(chosen.mealType, MealType.snack);

      // 缺省：上海 12:00 → lunch。
      final defaulted = await repository.addEntry(draft());
      expect(defaulted.mealType, MealType.lunch);

      // 缺省：UTC 2026-07-28 12:00 = 上海 20:00 → dinner（预判按本地时区）。
      final dinner = await repository.addEntry(
        RecordDraft(
          foodId: 'f-rice',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 7, 28, 12),
          source: EntrySource.manual,
        ),
      );
      expect(dinner.mealType, MealType.dinner);
      await repository.dispose();
    });

    test('当日记录流（今日餐次分组列表数据源）：入账/撤销实时可见', () async {
      final repository = repo();
      final entry = await repository.addEntry(draft());
      final entries = await db.foodEntryDao
          .watchEntriesForDate('anonymous', '2026-07-28')
          .first;
      expect(entries.map((e) => e.localId), contains(entry.localId));

      final undone = await repository.undo(entry.localId);
      expect(undone, isTrue);
      final afterUndo = await db.foodEntryDao
          .watchEntriesForDate('anonymous', '2026-07-28')
          .first;
      expect(afterUndo, isEmpty);
      await repository.dispose();
    });

    test('编辑记录改餐次落库；mealType 缺省保留原值', () async {
      final repository = repo();
      final entry = await repository.addEntry(draft()); // 预判 lunch
      expect(entry.mealType, MealType.lunch);

      // 显式改 snack：份量同值也要写入餐次列。
      final edited = await repository.updateEntry(
        entry.localId,
        amountG: 100,
        mealType: MealType.snack,
      );
      expect(edited.mealType, MealType.snack);
      expect(edited.amountG, 100);

      // 缺省 mealType=null → 保留已显式选择的 snack（不被预判覆写）。
      final kept = await repository.updateEntry(entry.localId, amountG: 150);
      expect(kept.mealType, MealType.snack);
      expect(kept.amountG, 150);
      await repository.dispose();
    });

    test('synced 行纯改餐次（份量不变）→ 不上行不轮换幂等键', () async {
      final repository = repo(undoWindow: const Duration(milliseconds: 30));
      final entry = await repository.addEntry(draft());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final synced = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(synced!.syncStatus, SyncStatus.synced);
      final pushesBefore = remote.pushCount;

      final edited = await repository.updateEntry(
        entry.localId,
        amountG: 100, // 与入账同值：纯餐次变更
        mealType: MealType.dinner,
      );
      expect(edited.mealType, MealType.dinner);
      // 纯本地列变更：状态/幂等键/版本全部不动，远程零新增请求。
      expect(edited.syncStatus, SyncStatus.synced);
      expect(edited.clientRequestId, synced.clientRequestId);
      expect(edited.localVersion, synced.localVersion);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(remote.pushCount, pushesBefore);
      await repository.dispose();
    });
  });

  group('断食期用餐标记（阶段 C，纯本地属性）', () {
    test('duringFast 入账落库 + 当日计数流；缺省 false', () async {
      final repository = repo();
      final fastingMeal = await repository.addEntry(
        RecordDraft(
          foodId: 'f-rice',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 7, 28, 4),
          source: EntrySource.manual,
          duringFast: true,
        ),
      );
      expect(fastingMeal.duringFast, isTrue);

      final normal = await repository.addEntry(draft());
      expect(normal.duringFast, isFalse);

      final count = await db.foodEntryDao
          .watchDuringFastCount('anonymous', '2026-07-28')
          .first;
      expect(count, 1);

      // 撤销窗内撤销 → 计数回落。
      final undone = await repository.undo(fastingMeal.localId);
      expect(undone, isTrue);
      final afterUndo = await db.foodEntryDao
          .watchDuringFastCount('anonymous', '2026-07-28')
          .first;
      expect(afterUndo, 0);
      await repository.dispose();
    });
  });
  group('乐观入账守卫（未入库食品先记）', () {
    test('引用未上行自定义食物的记录不上行、不 T7 回滚，保持 pending 待食物先行', () async {
      // 离线保存的自定义食物（customSyncPending=true，本地临时 id）。
      await db.foodDao.upsertAll(<FoodsCompanion>[
        const FoodsCompanion(
          id: Value('custom-local-1'),
          nameZh: Value('离线私房菜'),
          nameEn: Value('Offline Dish'),
          kcalPer100g: Value(200),
          proteinPer100g: Value(8),
          carbPer100g: Value(30),
          fatPer100g: Value(5),
          isCustom: Value(true),
          customSyncPending: Value(true),
          customClientRequestId: Value('req-1'),
        ),
      ]);
      remote.mode = FakeRemoteMode.offline;
      final repository = repo();
      final entry = await repository.addEntry(draft(foodId: 'custom-local-1'));
      expect(entry.syncStatus, SyncStatus.pending);

      // 联网重试：食物仍未上行 → 记录保持 pending，远程零请求（不放行吃 4xx）。
      remote.mode = FakeRemoteMode.success;
      await repository.retryPending();
      expect(remote.pushCount, 0);
      final kept = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(kept, isNotNull);
      expect(kept?.syncStatus, SyncStatus.pending);
      await repository.dispose();
    });

    test('食物上行后（customSyncPending=false）记录正常上行 synced', () async {
      await db.foodDao.upsertAll(<FoodsCompanion>[
        const FoodsCompanion(
          id: Value('cf-synced-1'),
          nameZh: Value('已上行私房菜'),
          nameEn: Value('Synced Dish'),
          kcalPer100g: Value(200),
          proteinPer100g: Value(8),
          carbPer100g: Value(30),
          fatPer100g: Value(5),
          isCustom: Value(true),
        ),
      ]);
      remote.mode = FakeRemoteMode.offline;
      final repository = repo();
      final entry = await repository.addEntry(draft(foodId: 'cf-synced-1'));

      remote.mode = FakeRemoteMode.success;
      await repository.retryPending();
      final syncedEntry = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(syncedEntry?.syncStatus, SyncStatus.synced);
      expect(syncedEntry?.serverId, isNotNull);
      await repository.dispose();
    });
  });

  group('进程重建恢复（走查 L1）', () {
    test('撤销窗 Timer 随进程丢失的 submitting 行由 retryPending 恢复上行', () async {
      final first = repo(undoWindow: const Duration(seconds: 30));
      final entry = await first.addEntry(draft());
      expect(entry.syncStatus, SyncStatus.submitting);
      // 模拟进程被杀：dispose 取消 pending Timer，新实例没有任何撤销窗状态。
      await first.dispose();

      final reopened = repo();
      final n = await reopened.retryPending();
      expect(n, 1, reason: 'submitting 行必须纳入重试（旧逻辑只扫 pending，永久滞留）');
      final after = await db.foodEntryDao.getByLocalId(entry.localId);
      expect(after!.syncStatus, SyncStatus.synced);
      await reopened.dispose();
    });
  });

  group('归属日键口径（localDateKeyOf，CI 时区分叉回归）', () {
    test('查询侧「今日」跟随仓储 location，不随进程本地时区（UTC 16:19 = 北京次日）', () {
      // v1.14.0 CI 红根因：CI（TZ=UTC）16:19 UTC 时北京已是次日 00:19，
      // 写入侧（repo.location）与 localDateKey(进程本地) 日期分叉，
      // 「今日记录」在 CI 查询落空。钉死查询侧口径 = repo.location。
      final shanghai = RecordRepository(
        db: db,
        remote: remote,
        location: tz.getLocation('Asia/Shanghai'),
      );
      final tokyo = RecordRepository(
        db: db,
        remote: remote,
        location: tz.getLocation('Asia/Tokyo'),
      );
      final utc = DateTime.utc(2026, 9, 29, 16, 19); // 北京/东京均为 09-30
      expect(shanghai.localDateKeyOf(utc), '2026-09-30');
      expect(tokyo.localDateKeyOf(utc), '2026-09-30');
      // 同日早些时刻：UTC 15:59 北京 23:59 仍当日，东京已次日（口径差异可见）。
      final earlier = DateTime.utc(2026, 9, 29, 15, 59);
      expect(shanghai.localDateKeyOf(earlier), '2026-09-29');
      expect(tokyo.localDateKeyOf(earlier), '2026-09-30');
    });
  });

  group('在途上行代际与删除失败保真', () {
    Future<
      ({
        RecordRepository repository,
        _ControlledRecordRemote remote,
        FoodEntry entry,
      })
    >
    inFlightScenario() async {
      final controlled = _ControlledRecordRemote();
      final repository = RecordRepository(
        db: db,
        remote: controlled,
        location: location,
      );
      addTearDown(repository.dispose);
      await db.foodEntryDao.insertEntry(
        const FoodEntriesCompanion(
          localId: Value('l-inflight'),
          userId: Value('anonymous'),
          serverId: Value('srv-inflight'),
          clientRequestId: Value('req-old'),
          syncStatus: Value(SyncStatus.submitting),
          localVersion: Value(2),
          serverVersion: Value(3),
          serverUpdatedAt: Value('2026-07-28T03:00:00.000Z'),
          retryCount: Value(0),
          deleted: Value(false),
          datetimeUtc: Value('2026-07-28T04:00:00.000Z'),
          localDate: Value('2026-07-28'),
          foodId: Value('f-rice'),
          amountG: Value(100),
          kcal: Value(116),
          proteinG: Value(2.6),
          carbG: Value(25.9),
          fatG: Value(0.3),
          source: Value(EntrySource.manual),
          createdAtUtc: Value('2026-07-28T04:00:00.000Z'),
          updatedAtUtc: Value('2026-07-28T04:10:00.000Z'),
        ),
      );
      return (
        repository: repository,
        remote: controlled,
        entry: (await db.foodEntryDao.getByLocalId('l-inflight'))!,
      );
    }

    test('旧 ack 不标 synced 新编辑：保留新内容/新幂等键，采用新基线转 pending', () async {
      final scenario = await inFlightScenario();
      final push = scenario.repository.flushEntry(scenario.entry.localId);
      await scenario.remote.started.future;
      final edited = await scenario.repository.updateEntry(
        scenario.entry.localId,
        amountG: 200,
      );
      scenario.remote.firstOutcome.complete(
        const PushAck(
          serverId: 'srv-inflight',
          serverVersion: 7,
          serverUpdatedAtUtc: '2026-07-28T05:00:00.000Z',
        ),
      );
      await push;

      var current = (await db.foodEntryDao.getByLocalId(edited.localId))!;
      expect(current.amountG, 200);
      expect(current.syncStatus, SyncStatus.pending);
      expect(current.clientRequestId, edited.clientRequestId);
      expect(current.clientRequestId, isNot('req-old'));
      expect(current.serverVersion, 7);
      expect(current.serverUpdatedAt, '2026-07-28T05:00:00.000Z');

      await scenario.repository.retryPending();
      current = (await db.foodEntryDao.getByLocalId(edited.localId))!;
      expect(current.syncStatus, SyncStatus.synced);
      expect(
        scenario.remote.pushed.last.clientRequestId,
        edited.clientRequestId,
      );
      expect(scenario.remote.pushed.last.serverVersion, 7);
    });

    test('旧 reject 不删在途新编辑、不发旧失败事件：新内容转 pending 可重试', () async {
      final scenario = await inFlightScenario();
      final failures = <RecordSyncFailure>[];
      final subscription = scenario.repository.failures.listen(failures.add);
      addTearDown(subscription.cancel);
      final push = scenario.repository.flushEntry(scenario.entry.localId);
      await scenario.remote.started.future;
      final edited = await scenario.repository.updateEntry(
        scenario.entry.localId,
        amountG: 200,
      );
      scenario.remote.firstOutcome.complete(
        const PushReject('VALIDATION_ERROR'),
      );
      await push;

      final current = (await db.foodEntryDao.getByLocalId(edited.localId))!;
      expect(current.amountG, 200);
      expect(current.syncStatus, SyncStatus.pending);
      expect(current.clientRequestId, edited.clientRequestId);
      expect(current.serverVersion, 3);
      expect(current.lastError, isNull);
      expect(failures, isEmpty);

      await scenario.repository.retryPending();
      expect(
        scenario.remote.pushed.last.clientRequestId,
        edited.clientRequestId,
      );
      expect(scenario.remote.pushed.last.serverVersion, 3);
    });

    test('旧 conflict 不覆盖在途新编辑：采用冲突新基线转 pending，后续 update 换新幂等键', () async {
      final scenario = await inFlightScenario();
      final push = scenario.repository.flushEntry(scenario.entry.localId);
      await scenario.remote.started.future;
      final edited = await scenario.repository.updateEntry(
        scenario.entry.localId,
        amountG: 200,
      );
      scenario.remote.firstOutcome.complete(
        const PushConflict(
          serverVersion: 9,
          serverUpdatedAtUtc: '2026-07-28T06:00:00.000Z',
        ),
      );
      await push;

      final current = (await db.foodEntryDao.getByLocalId(edited.localId))!;
      expect(current.amountG, 200);
      expect(current.syncStatus, SyncStatus.pending);
      expect(current.clientRequestId, edited.clientRequestId);
      expect(current.clientRequestId, isNot('req-old'));
      expect(current.serverVersion, 9);
      expect(current.serverUpdatedAt, '2026-07-28T06:00:00.000Z');
      expect(current.lastError, isNull);

      await scenario.repository.retryPending();
      expect(
        scenario.remote.pushed.last.clientRequestId,
        edited.clientRequestId,
      );
      expect(scenario.remote.pushed.last.serverVersion, 9);
    });

    test(
      'delete 被 VALIDATION_ERROR 拒绝：保留 pending tombstone + lastError',
      () async {
        final scenario = await inFlightScenario();
        await db.foodEntryDao.updateEntry(
          scenario.entry.localId,
          const FoodEntriesCompanion(syncStatus: Value(SyncStatus.synced)),
        );
        final repository = RecordRepository(
          db: db,
          remote: FakeRecordRemote(mode: FakeRemoteMode.reject),
          location: location,
        );
        addTearDown(repository.dispose);

        expect(await repository.deleteEntry(scenario.entry.localId), isTrue);

        final current = (await db.foodEntryDao.getByLocalId(
          scenario.entry.localId,
        ))!;
        expect(current.deleted, isTrue);
        expect(current.syncStatus, SyncStatus.pending);
        expect(current.lastError, 'VALIDATION_FAILED');
      },
    );
  });
}

final class _ControlledRecordRemote implements RecordRemote {
  final Completer<PushOutcome> firstOutcome = Completer<PushOutcome>();
  final Completer<void> started = Completer<void>();
  final List<FoodEntry> pushed = <FoodEntry>[];

  @override
  bool get isOnline => true;

  @override
  Future<PushOutcome> push(FoodEntry entry) {
    pushed.add(entry);
    if (pushed.length == 1) {
      started.complete();
      return firstOutcome.future;
    }
    return Future<PushOutcome>.value(
      PushAck(
        serverId: entry.serverId ?? 'srv-new',
        serverVersion: (entry.serverVersion ?? 0) + 1,
        serverUpdatedAtUtc: '2026-07-28T07:00:00.000Z',
      ),
    );
  }
}

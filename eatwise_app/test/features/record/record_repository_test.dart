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

        final updated = await repository.updateAmount(entry.localId, 200);
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
      final updated = await repository.updateAmount(entry.localId, 200);
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

      expect(() => repository.addEntry(draft(amountG: 0)), throwsArgumentError);
      expect(
        () => repository.addEntry(draft(foodId: 'f-unknown')),
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
}

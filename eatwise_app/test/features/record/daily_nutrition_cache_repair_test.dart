import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/daily_nutrition_cache_repair.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// 聚合缓存存量回填修复测试（v1.12.5 走查盲区：旧版本下行遗留记录
/// 不经重算、sync 游标已越过 → 首页/趋势假空不自愈）。
void main() {
  late AppDatabase db;
  late DailyNutritionCacheRepair repair;

  setUp(() async {
    db = AppDatabase.memory();
    repair = DailyNutritionCacheRepair(db: db);
    await seedFoods(db);
    addTearDown(() async => db.close());
  });

  FoodEntry entry({
    required String localId,
    String userId = 'u-1',
    required String localDate,
    String datetimeUtc = '2026-09-19T01:10:00.000Z',
    String updatedAtUtc = '2026-09-19T01:10:00.000Z',
    double amountG = 200,
    double kcal = 232,
    bool deleted = false,
  }) {
    return FoodEntry(
      localId: localId,
      userId: userId,
      serverId: 'srv-$localId',
      clientRequestId: 'cr-$localId',
      syncStatus: SyncStatus.synced,
      localVersion: 1,
      serverVersion: 1,
      serverUpdatedAt: updatedAtUtc,
      retryCount: 0,
      lastError: null,
      deleted: deleted,
      datetimeUtc: datetimeUtc,
      localDate: localDate,
      foodId: 'f-rice',
      amountG: amountG,
      kcal: kcal,
      proteinG: 5.2,
      carbG: 51.8,
      fatG: 0.6,
      source: EntrySource.manual,
      note: null,
      duringFast: false,
      mealType: null,
      createdAtUtc: datetimeUtc,
      updatedAtUtc: updatedAtUtc,
    );
  }

  String todayKey() => localDateKey(DateTime.now());
  String daysAgoKey(int n) =>
      localDateKey(DateTime.now().toLocal().subtract(Duration(days: n)));

  group('DailyNutritionCacheRepair', () {
    test('存量盲区：entries 有数据、缓存空 → repairAll 后两日缓存齐备（首页/趋势同源恢复）', () async {
      // 模拟旧版本下行遗留：两条不同归属日的 synced 记录，缓存表空。
      final today = todayKey();
      final old = daysAgoKey(20);
      await db.foodEntryDao.insertEntry(
        entry(localId: 'l-1', localDate: today).toCompanion(true),
      );
      await db.foodEntryDao.insertEntry(
        entry(localId: 'l-2', localDate: old, kcal: 116).toCompanion(true),
      );

      final repaired = await repair.repairAll('u-1');

      expect(repaired, 2);
      final todayCache = await db.foodEntryDao.getDailyNutrition('u-1', today);
      expect(todayCache, isNotNull);
      expect(todayCache!.entryCount, 1);
      expect(todayCache.kcal, 232);
      final oldCache = await db.foodEntryDao.getDailyNutrition('u-1', old);
      expect(oldCache!.kcal, 116);
    });

    test('缓存过期（entries 比 cache 新）→ 重算刷新；缓存新鲜 → 跳过不动', () async {
      final today = todayKey();
      await db.foodEntryDao.insertEntry(
        entry(
          localId: 'l-1',
          localDate: today,
          updatedAtUtc: '2026-09-19T02:00:00.000Z',
        ).toCompanion(true),
      );
      // 过期缓存：合计值陈旧（只算了 100 kcal）且时间早于记录修改时间。
      await db.foodEntryDao.recomputeDailyNutrition(
        'u-1',
        today,
        updatedAtUtc: '2026-09-19T01:00:00.000Z',
      );
      // 再插入一条更新的记录（缓存未跟上）。
      await db.foodEntryDao.insertEntry(
        entry(
          localId: 'l-2',
          localDate: today,
          kcal: 116,
          updatedAtUtc: '2026-09-19T03:00:00.000Z',
        ).toCompanion(true),
      );

      final repaired = await repair.repairAll('u-1');

      expect(repaired, 1);
      final cache = await db.foodEntryDao.getDailyNutrition('u-1', today);
      expect(cache!.entryCount, 2);
      expect(cache.kcal, 348);

      // 再跑一轮：缓存已新鲜 → 全跳过（幂等，不重复重算）。
      expect(await repair.repairAll('u-1'), 0);
    });

    test('repairRecent 只覆盖近 7 天：旧日期缺失缓存不补，窗口内补齐', () async {
      final recent = daysAgoKey(3);
      final ancient = daysAgoKey(30);
      await db.foodEntryDao.insertEntry(
        entry(localId: 'l-1', localDate: recent).toCompanion(true),
      );
      await db.foodEntryDao.insertEntry(
        entry(localId: 'l-2', localDate: ancient).toCompanion(true),
      );

      final repaired = await repair.repairRecent('u-1');

      expect(repaired, 1);
      expect(await db.foodEntryDao.getDailyNutrition('u-1', recent), isNotNull);
      expect(await db.foodEntryDao.getDailyNutrition('u-1', ancient), isNull);
    });

    test('tombstone 记录不占归属日（删除后日期不产生缓存）', () async {
      final today = todayKey();
      await db.foodEntryDao.insertEntry(
        entry(
          localId: 'l-1',
          localDate: today,
          deleted: true,
        ).toCompanion(true),
      );

      expect(await repair.repairAll('u-1'), 0);
      expect(await db.foodEntryDao.getDailyNutrition('u-1', today), isNull);
    });
  });

  group('RecordSyncEngine 挂载（上一轮盲区场景回归）', () {
    test('本地已有旧版本下行遗留记录 + 缓存空 + pull 无新变更 → syncNow 后缓存回填', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final today = todayKey();
      // 旧版本遗留：记录已在本机（synced），缓存表空，sync 游标已越过
      // （FakeRecordRemote → 引擎不做下行，模拟 pull 0 变更）。
      await db.foodEntryDao.insertEntry(
        entry(localId: 'l-1', localDate: today).toCompanion(true),
      );
      final repo = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
        userId: 'u-1',
      );
      final engine = RecordSyncEngine(
        repository: repo,
        prefs: prefs,
        cacheRepair: repair,
      );

      await engine.syncNow();

      final cache = await db.foodEntryDao.getDailyNutrition('u-1', today);
      expect(cache, isNotNull);
      expect(cache!.entryCount, 1);
      expect(cache.kcal, 232);
      // 全量回填完成标记已落（下轮走廉价窗口）。
      expect(prefs.getBool('daily_cache_backfill_v1_u-1'), isTrue);

      // 标记后：今日记录被本地修改使缓存过期 → 下轮 syncNow 近 7 天窗口兜住。
      final futureIso = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      await db.foodEntryDao.updateEntry(
        'l-1',
        FoodEntriesCompanion(
          kcal: const Value(500),
          updatedAtUtc: Value(futureIso),
        ),
      );
      await engine.syncNow();
      final refreshed = await db.foodEntryDao.getDailyNutrition('u-1', today);
      expect(refreshed!.kcal, 500);

      await repo.dispose();
    });
  });
}

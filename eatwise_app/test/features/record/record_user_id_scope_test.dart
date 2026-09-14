import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart' show EntrySource;
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'record_test_helper.dart';

/// 读写口径回归（v1.1.1 走查 R2）：写入侧 record/water 仓储必须与读取侧
/// （数据页 NutritionDataSource）同口径取 currentUserIdProvider——否则登录
/// 用户写入落 anonymous、数据页按真实 userId 查询恒空。
void main() {
  // 固定时钟：2026-07-28 14:00（UTC；tz.local 未 setLocalLocation 时为 UTC）。
  final now = DateTime.utc(2026, 7, 28, 14);

  late AppDatabase db;
  late SharedPreferences prefs;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  /// 模拟登录用户 u-123 的装配（currentUserIdProvider 为唯一口径来源）。
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        recordRemoteProvider.overrideWithValue(FakeRecordRemote()),
        currentUserIdProvider.overrideWithValue('u-123'),
        nutritionNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('装配口径：record/water 仓储 userId 取 currentUserIdProvider', () {
    final container = makeContainer();

    expect(container.read(recordRepositoryProvider).userId, 'u-123');
    expect(container.read(waterLogRepositoryProvider).userId, 'u-123');
  });

  test('登录 userId 下写入饮食记录 → 数据页当日聚合同源可读', () async {
    final container = makeContainer();

    await container
        .read(recordRepositoryProvider)
        .addEntry(
          RecordDraft(
            foodId: 'f-rice',
            amountG: 100,
            mealUtc: DateTime.utc(2026, 7, 28, 4),
            source: EntrySource.manual,
          ),
        );

    // 数据页读取链：dayCacheProvider → nutritionDataSourceProvider
    // （currentUserIdProvider 口径）。写读同口径时必须能读到当日聚合。
    final cache = await container.read(dayCacheProvider.future);
    expect(cache, isNotNull);
    expect(cache!.userId, 'u-123');
    expect(cache.entryCount, 1);
    expect(cache.kcal, 116); // 白米饭 116 kcal/100g × 100g
  });

  test('登录 userId 下写入饮水记录 → 当日累计同源可读', () async {
    final container = makeContainer();
    final repo = container.read(waterLogRepositoryProvider);

    await repo.add(300);

    final total = await repo
        .watchTotalForDate(localDateKey(DateTime.now()))
        .first;
    expect(total, 300);
  });
}

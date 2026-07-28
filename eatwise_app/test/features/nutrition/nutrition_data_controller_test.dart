import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 数据页 application 层单测：日期切换、无数据空态、阈值边界三色、
/// 兜底目标、近 7 日趋势对齐（D-04/D-05 / PRD M4）。
void main() {
  // 固定时钟：2026-07-28 14:00 本地。
  final now = DateTime(2026, 7, 28, 14);

  late AppDatabase db;
  late SharedPreferences prefs;

  Future<void> seedGoal({bool withSnapshot = true}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    if (withSnapshot) {
      SharedPreferencesOnboardingStore(prefs).saveNutritionGoal(
        NutritionGoalSnapshot(
          targetKcal: 2000,
          proteinG: 100,
          carbG: 200,
          fatG: 60,
          usedFallback: false,
          configVersion: '1.0.0',
        ),
      );
    }
  }

  Future<void> seedCache(
    String date, {
    required double kcal,
    double proteinG = 0,
    double carbG = 0,
    double fatG = 0,
    int entryCount = 1,
  }) {
    return db
        .into(db.dailyNutritionCaches)
        .insert(
          DailyNutritionCachesCompanion(
            userId: const Value('anonymous'),
            date: Value(date),
            entryCount: Value(entryCount),
            kcal: Value(kcal),
            proteinG: Value(proteinG),
            carbG: Value(carbG),
            fatG: Value(fatG),
            updatedAtUtc: Value(now.toUtc().toIso8601String()),
          ),
        );
  }

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        nutritionNowProvider.overrideWithValue(now),
      ],
    );
  }

  setUp(() async {
    db = AppDatabase.memory();
    await seedGoal();
  });

  tearDown(() async {
    await db.close();
  });

  group('日期切换', () {
    test('初始为今天；今天不可再往后翻（PRD M4：不可超今天）', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedDateProvider), DateTime(2026, 7, 28));
      expect(container.read(canGoNextDayProvider), isFalse);
      expect(container.read(isTodaySelectedProvider), isTrue);

      // 今天点「后一天」不动作。
      container.read(selectedDateProvider.notifier).nextDay();
      expect(container.read(selectedDateProvider), DateTime(2026, 7, 28));
    });

    test('前一天/后一天/回到今天 联动可用态', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(selectedDateProvider.notifier).prevDay();
      expect(container.read(selectedDateProvider), DateTime(2026, 7, 27));
      expect(container.read(canGoNextDayProvider), isTrue);
      expect(container.read(isTodaySelectedProvider), isFalse);

      container.read(selectedDateProvider.notifier).nextDay();
      expect(container.read(selectedDateProvider), DateTime(2026, 7, 28));
      expect(container.read(canGoNextDayProvider), isFalse);

      container.read(selectedDateProvider.notifier).prevDay();
      container.read(selectedDateProvider.notifier).prevDay();
      expect(container.read(selectedDateProvider), DateTime(2026, 7, 26));
      container.read(selectedDateProvider.notifier).backToToday();
      expect(container.read(selectedDateProvider), DateTime(2026, 7, 28));
      expect(container.read(isTodaySelectedProvider), isTrue);
    });
  });

  group('信号灯判定（D-05）', () {
    test('当日无记录 → hasData=false，总结走空态（不显示信号灯）', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(dayCacheProvider.future);
      expect(container.read(dayIntakeProvider), isNull);
      expect(container.read(daySignalsProvider).hasData, isFalse);
      expect(container.read(daySummaryProvider), DaySummaryTone.empty);
    });

    test('阈值边界：热量 85% 绿 / 84.9% 黄 / >130% 红（闭区间，未取整判定）', () async {
      // 第一天四项全绿（kcal 85% 闭端点绿，其余 100% 绿）。
      await seedCache(
        '2026-07-28',
        kcal: 1700, // 85.0% → 绿（闭端点）
        proteinG: 100, // 100% → 绿
        carbG: 200, // 100% → 绿
        fatG: 60, // 100% → 绿
      );
      await seedCache('2026-07-27', kcal: 1698); // 84.9% → 黄-低
      await seedCache('2026-07-26', kcal: 2620); // 131% → 红-高

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(dayCacheProvider.future);
      expect(
        container.read(daySignalsProvider).verdicts[NutrientType.kcal]!.zone,
        SignalZone.green,
      );
      expect(container.read(daySummaryProvider), DaySummaryTone.allGreen);

      container.read(selectedDateProvider.notifier).prevDay();
      await container.read(dayCacheProvider.future);
      expect(
        container.read(daySignalsProvider).verdicts[NutrientType.kcal]!.zone,
        SignalZone.yellow,
      );
      // 其余营养素零摄入（p=0 < yellowLow）→ 红，总结 hasRed 优先于黄。
      expect(container.read(daySummaryProvider), DaySummaryTone.hasRed);

      container.read(selectedDateProvider.notifier).prevDay();
      await container.read(dayCacheProvider.future);
      expect(
        container.read(daySignalsProvider).verdicts[NutrientType.kcal]!.zone,
        SignalZone.red,
      );
    });

    test('建议 key：绿区走 green 模板，零摄入营养素走 zero 文案 key（§4.4）', () async {
      await seedCache('2026-07-28', kcal: 2000, proteinG: 100);
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(dayCacheProvider.future);
      final keys = container.read(daySignalsProvider).adviceKeys;
      expect(keys, contains('nutrition.signalCard.advice.kcal.green'));
      expect(keys, contains('nutrition.signalCard.advice.protein.green'));
      expect(keys, contains('nutrition.signalCard.advice.carb.zero'));
      expect(keys, contains('nutrition.signalCard.advice.fat.zero'));
    });
  });

  group('营养目标（D-04）', () {
    test('M1 快照存在 → 用快照目标（不兜底）', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final goal = container.read(nutritionGoalProvider);
      expect(goal.targetKcal, 2000);
      expect(goal.usedFallback, isFalse);
    });

    test('缺资料 → 兜底目标 usedFallback=true（驱动补全提示）', () async {
      await seedGoal(withSnapshot: false);
      final container = makeContainer();
      addTearDown(container.dispose);
      final goal = container.read(nutritionGoalProvider);
      expect(goal.usedFallback, isTrue);
      expect(goal.targetKcal, 2000); // 性别缺失兜底 2000 kcal
    });
  });

  group('近 7 日趋势', () {
    test('序列长度 7、按日期升序对齐、无记录日为 null、随日期切换联动', () async {
      await seedCache('2026-07-28', kcal: 2000);
      await seedCache('2026-07-25', kcal: 1500);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(weeklyTrendProvider.future);
      expect(container.read(weeklyKcalProvider), <double?>[
        null,
        null,
        null,
        1500,
        null,
        null,
        2000,
      ]);

      // 切到前一天：窗口整体前移一天（07-21..07-27，07-25 在 index 4）。
      container.read(selectedDateProvider.notifier).prevDay();
      await container.read(weeklyTrendProvider.future);
      expect(container.read(weeklyKcalProvider), <double?>[
        null,
        null,
        null,
        null,
        1500,
        null,
        null,
      ]);
    });

    test('entryCount=0 的缓存行不计入趋势（防御脏数据）', () async {
      await seedCache('2026-07-28', kcal: 0, entryCount: 0);
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(weeklyTrendProvider.future);
      expect(container.read(weeklyKcalProvider), List<double?>.filled(7, null));
    });
  });
}

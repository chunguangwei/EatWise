import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/presentation/reports_page.dart';
import 'package:eatwise/features/reports/presentation/trend_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M6 报告页 widget 测试：三维切换、7/30 切换、空态引导、周报卡、双语。
void main() {
  final now = DateTime(2026, 7, 28, 14); // 周二

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
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
    db = AppDatabase.memory();
    addTearDown(() async {
      await db.close();
    });
  });

  Future<void> seedNutrition(String date, double kcal, {int entries = 2}) {
    return db
        .into(db.dailyNutritionCaches)
        .insert(
          DailyNutritionCachesCompanion(
            userId: const Value('anonymous'),
            date: Value(date),
            entryCount: Value(entries),
            kcal: Value(kcal),
            proteinG: const Value(100),
            carbG: const Value(200),
            fatG: const Value(60),
            updatedAtUtc: Value(now.toUtc().toIso8601String()),
          ),
        );
  }

  Future<void> seedFast(String date, int hours, {bool qualified = true}) {
    return db
        .into(db.fastingRecords)
        .insert(
          FastingRecordsCompanion(
            localId: Value('anonymous-$date'),
            userId: const Value('anonymous'),
            attributionDate: Value(date),
            startUtc: const Value(0),
            endUtc: Value(hours * 3600),
            actualSec: Value(hours * 3600),
            plannedSec: Value(hours * 3600),
            extendedMinutes: const Value(0),
            result: const Value('completed'),
            qualified: Value(qualified),
            clientRequestId: Value('req-$date'),
            syncStatus: const Value(SyncStatus.synced),
            createdAtUtc: Value(now.toUtc().toIso8601String()),
          ),
        );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            reportsNowProvider.overrideWithValue(now),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            // 与 main.dart 对齐：slang locale + 官方 delegates，
            // DateFormat 才能按当前语言取到日期符号（zh_CN 等）。
            locale: LocaleSettings.currentLocale.flutterLocale,
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const ReportsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 趋势折线 CustomPaint（按 painter 类型，排除 Material 内部 CustomPaint）。
  Finder findTrendPainter() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ReportTrendPainter,
  );

  testWidgets('全无数据：趋势/成长轨迹/周报各自走引导空态，无空坐标轴', (tester) async {
    await pumpPage(tester);

    // 趋势空态（默认热量维度 → CTA 去记录）。
    expect(find.text('数据曲线正在热身，多记几天它就跑起来啦'), findsOneWidget);
    expect(find.text('去记录'), findsWidgets);
    // 成长轨迹空态。
    expect(find.text('还没有足迹，先记一笔或完成一次断食吧'), findsOneWidget);
    // 无折线渲染（按 painter 类型判定，排除 Material 内部 CustomPaint）。
    expect(findTrendPainter(), findsNothing);

    // 周报与月报在首屏外，滚动露出（Sliver 懒加载）。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    // 周报空态。
    expect(find.text('周报还差一点点数据，记一笔或完成一次断食就生成啦'), findsOneWidget);
    // 月报卡：月份标题 + 空态引导。
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('本月暂无记录'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('三维切换：断食/体重空态 CTA 随维度变化', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('断食时长'));
    await tester.pump();
    expect(find.text('去断食'), findsOneWidget);

    await tester.tap(find.text('体重'));
    await tester.pump();
    expect(find.text('记体重'), findsOneWidget);
    expect(find.text('去断食'), findsNothing);

    await unmount(tester);
  });

  testWidgets('7/30 天切换：成长轨迹卡标题联动', (tester) async {
    await pumpPage(tester);

    expect(find.text('7 天成长轨迹'), findsOneWidget);
    await tester.tap(find.text('30 天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('30 天成长轨迹'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('有数据：折线渲染 + 成长轨迹数值 + 周报统计', (tester) async {
    await seedNutrition('2026-07-26', 2000, entries: 3);
    await seedNutrition('2026-07-28', 1600);
    await seedFast('2026-07-26', 16);
    await seedFast('2026-07-27', 14, qualified: false);
    await WeightLogStore(prefs).save('2026-07-26', 65.0);
    await WeightLogStore(prefs).save('2026-07-28', 64.4);
    await pumpPage(tester);

    // 折线渲染，无趋势空态。
    expect(findTrendPainter(), findsOneWidget);
    expect(find.text('数据曲线正在热身，多记几天它就跑起来啦'), findsNothing);
    // 成长轨迹四格。
    expect(find.text('断食达标'), findsOneWidget);
    expect(find.text('1 天'), findsOneWidget); // 仅 7/26 达标
    expect(find.text('记录天数'), findsOneWidget);
    expect(find.text('2 天'), findsOneWidget); // 7/26、7/28
    expect(find.text('15.0 小时'), findsOneWidget); // (16+14)/2
    expect(find.text('-0.6 公斤'), findsOneWidget); // 体重 Δ
    // 周报（本周 7/27～7/28）：记录 2 条，绿占比 75%（热量 80% 黄）。
    expect(find.text('记录 2 条'), findsOneWidget);
    expect(find.text('绿灯占比 75%'), findsOneWidget);
    expect(find.textContaining('周报还差一点点数据'), findsNothing);

    await unmount(tester);
  });

  testWidgets('月报卡：月份切换（未来月不可达）+ 四项统计 + 切到空月走空态', (tester) async {
    await seedNutrition('2026-07-26', 2000, entries: 3);
    await seedNutrition('2026-07-28', 1600);
    await seedFast('2026-07-26', 16);
    await seedFast('2026-07-27', 14, qualified: false);
    await WeightLogStore(prefs).save('2026-07-26', 65.0);
    await WeightLogStore(prefs).save('2026-07-28', 64.4);
    await pumpPage(tester);

    // 月报卡在首屏外，滚动露出。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 当月（2026-07）四项统计。
    expect(find.text('断食达标 1 天'), findsOneWidget); // 仅 7/26 达标
    expect(find.text('记录 3 天'), findsOneWidget); // 断食 7/26、7/27 ∪ 饮食 7/26、7/28
    expect(find.text('平均断食 15 小时'), findsOneWidget); // (16+14)/2
    expect(find.text('月均热量 1800 千卡 · 目标 2000 千卡'), findsOneWidget);
    expect(find.text('蛋白质 100g · 碳水 200g · 脂肪 60g'), findsOneWidget);
    expect(find.text('体重变化 −0.6 kg'), findsOneWidget);

    // 下一月是未来月（now=2026-07-28）→ 禁用；上一月可切。
    final nextButton = find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2026年6月'), findsOneWidget);
    // 6 月无数据 → 空态。
    expect(find.text('本月暂无记录'), findsOneWidget);
    expect(find.text('断食达标 1 天'), findsNothing);

    // 从 6 月可以回到 7 月。
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('断食达标 1 天'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('英文渲染：维度/范围/周报双语', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpPage(tester);

    expect(find.text('Growth trends'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Fasting'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('30D'), findsOneWidget);
    expect(find.text('7-day journey'), findsOneWidget);
    expect(
      find.text(
        'Your trends are warming up — log a few days to get them moving.',
      ),
      findsOneWidget,
    );

    // 周报与月报在首屏外，滚动露出。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('No records this month yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });
}

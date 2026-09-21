import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/nutrition/presentation/nutrition_data_page.dart';
import 'package:eatwise/features/nutrition/presentation/pro_details.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 数据页 widget 测试：四卡三重编码、折叠展开、趋势图空态、日期切换、
/// 双语切换、英文长文截断（PRD M4 / 四态规范 4.1 / M8 无障碍硬性）。
void main() {
  final now = DateTime(2026, 7, 28, 14); // 周二 14:00 → 午餐餐段

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    // 组件级曝光埋点（ExposureTracker）：即时分发可视回调，避免插件默认
    // 500ms 聚合 Timer 在卸载时未决。
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
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

  Future<void> seedToday({
    required double kcal,
    required double proteinG,
    required double carbG,
    required double fatG,
  }) {
    return db
        .into(db.dailyNutritionCaches)
        .insert(
          DailyNutritionCachesCompanion(
            userId: const Value('anonymous'),
            date: const Value('2026-07-28'),
            entryCount: const Value(2),
            kcal: Value(kcal),
            proteinG: Value(proteinG),
            carbG: Value(carbG),
            fatG: Value(fatG),
            updatedAtUtc: Value(now.toUtc().toIso8601String()),
          ),
        );
  }

  Future<void> pumpPage(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            nutritionNowProvider.overrideWithValue(now),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const NutritionDataPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 收尾：卸载并多次 pump（冲刷 drift 退订的 Timer.run）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('信号灯四卡：三重编码（色+图标+文字）+ 大数值；建议收进徽标弹窗', (tester) async {
    // kcal 1700（85% 绿）；protein 75（75% 黄）；carb 80（40% 红）；
    // fat 60（100% 绿）。
    await seedToday(kcal: 1700, proteinG: 75, carbG: 80, fatG: 60);
    await pumpPage(tester);

    // 四营养素卡。
    for (final name in <String>['热量', '蛋白质', '碳水', '脂肪']) {
      expect(find.text(name), findsWidgets);
    }
    // 三重编码：图标 + 文字（色由 token 保证，语义不靠颜色）。
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2)); // 绿 ×2
    expect(find.byIcon(Icons.error), findsOneWidget); // 黄 ×1
    expect(find.byIcon(Icons.cancel), findsOneWidget); // 红 ×1
    expect(find.text('达标'), findsNWidgets(2));
    expect(find.text('适量提醒'), findsOneWidget);
    expect(find.text('警示'), findsOneWidget);
    // 大数值（已摄入）与目标。
    expect(find.text('1700'), findsOneWidget);
    expect(find.text('/ 目标 2000 千卡'), findsOneWidget);
    // 一句话建议不再占卡面（瘦身）；点红区碳水徽标弹详情对话框读全。
    expect(find.textContaining('今天碳水太少了'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('signal.zone.NutrientType.carb')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('今天碳水太少了'), findsOneWidget);
    expect(find.textContaining('午餐来份掌心大的瘦肉或豆腐'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('今天碳水太少了'), findsNothing);
    // 总结 H2：有红 → 温和引导。
    expect(find.textContaining('有几盏小红灯'), findsOneWidget);
    // 无记录空态不出现。
    expect(find.text('去记录'), findsNothing);

    await unmount(tester);
  });

  testWidgets('专业数据默认折叠，点「查看详情」展开 RDA，可再收起', (tester) async {
    await seedToday(kcal: 2000, proteinG: 100, carbG: 200, fatG: 60);
    await pumpPage(tester);

    // 折叠态：区块高度 ≈ 头部一行（AnimatedCrossFade 隐藏子树仍在树中，
    // 以渲染高度判定可见性）。
    double sectionHeight() =>
        tester.getSize(find.byType(ProDetailsSection)).height;
    final collapsedHeight = sectionHeight();
    expect(find.text('查看详情'), findsOneWidget);
    expect(collapsedHeight, lessThan(80));

    await tester.tap(find.text('查看详情'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sectionHeight(), greaterThan(collapsedHeight + 100));
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('100%'), findsNWidgets(4)); // 四项占比均 100%
    expect(find.textContaining('待营养专业背书'), findsOneWidget);

    await tester.tap(find.text('收起'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sectionHeight(), lessThan(80));

    await unmount(tester);
  });

  testWidgets('当日无记录 → 空态引导去记录，不显示误导性信号灯（D-05）', (tester) async {
    await pumpPage(tester);

    // 当日空态 CTA + 趋势空态 CTA（薄荷走查 P2 补齐）各一个。
    expect(find.text('去记录'), findsNWidgets(2));
    expect(find.text('数据曲线正在热身，多记几天它就跑起来啦。'), findsOneWidget);
    // 无信号灯图标、无专业数据区。
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);
    expect(find.text('专业数据'), findsNothing);
    // 总结走空态文案。
    expect(find.textContaining('这一天还没有记录'), findsOneWidget);
    // 趋势图也无数据 → 独立空态引导。
    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('日期切换：今天「后一天」禁用；切到昨天显示「回到今天」', (tester) async {
    await seedToday(kcal: 2000, proteinG: 100, carbG: 200, fatG: 60);
    await pumpPage(tester);

    final nextButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(nextButton.onPressed, isNull); // 不可超今天
    expect(find.text('回到今天'), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('回到今天'), findsOneWidget);
    // 昨天无记录 → 空态（当日空态 + 趋势空态各一个 CTA）。
    expect(find.text('去记录'), findsNWidgets(2));

    await tester.tap(find.text('回到今天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1700'), findsNothing);
    expect(find.text('2000'), findsOneWidget); // 回到今天的大数值

    await unmount(tester);
  });

  testWidgets('趋势图有数据时渲染折线（CustomPaint），无空态文案', (tester) async {
    await seedToday(kcal: 2000, proteinG: 100, carbG: 200, fatG: 60);
    await pumpPage(tester);

    expect(find.text('近 7 日趋势'), findsOneWidget);
    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);

    // 切到断食时长：历史未持久化 → 空态引导（〔遗留〕M6 接入）。
    await tester.tap(find.text('断食时长'));
    await tester.pump();
    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('英文渲染：三重编码/折叠/建议双语，窄屏长文截断不破版', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await seedToday(kcal: 1700, proteinG: 75, carbG: 80, fatG: 60);
    await pumpPage(tester, size: const Size(1080, 2532)); // 360 逻辑宽

    expect(find.text('Calories'), findsWidgets);
    expect(find.text('Protein'), findsWidgets);
    expect(find.text('On track'), findsNWidgets(2));
    expect(find.text('Heads-up'), findsOneWidget);
    expect(find.text('Warning'), findsOneWidget);
    // 建议收进徽标弹窗：窄屏下卡面无建议长文，点开弹窗读全。
    expect(find.textContaining('Carbs are well under today'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('signal.zone.NutrientType.carb')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 截断规则：营养名单行 ellipsis；弹窗内建议不截断（四态规范 4.1）。
    final nameText = tester.widget<Text>(find.text('Calories').first);
    expect(nameText.maxLines, 1);
    expect(nameText.overflow, TextOverflow.ellipsis);
    final adviceText = tester.widget<Text>(
      find.textContaining('Carbs are well under today'),
    );
    expect(adviceText.overflow, isNull); // 建议必须读全，不允许截断
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 折叠区在首屏外（Sliver 懒加载），先滚动露出再展开。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('View details'), findsOneWidget);
    await tester.tap(find.text('View details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('RDA ref.'), findsOneWidget);

    expect(tester.takeException(), isNull); // 无溢出错

    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });
}

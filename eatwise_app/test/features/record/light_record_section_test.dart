import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/light_record_section.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M3 轻量记录区 widget 测试（PRD M3 功能点 4）：饮水快捷档位 / 当日累计 /
/// D-11 撤销、体重输入校验 / 同日覆写、中英双语。
void main() {
  late AppDatabase db;
  late WaterLogRepository waterRepo;
  late SharedPreferences prefs;
  late WeightLogStore weightStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    weightStore = WeightLogStore(prefs);
    db = AppDatabase.memory();
    waterRepo = WaterLogRepository(db: db);
    addTearDown(() async => db.close());
  });

  String todayKey() => localDateKey(DateTime.now());

  /// 测试收尾：失焦输入框 → 隐藏吐司（取消时长 Timer）→ 卸载并多次 pump
  /// （drift 流退订经 `Timer.run` 清理，须冲刷假时钟区，同 record_page_test）。
  Future<void> settleUi(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffolds = find.byType(Scaffold);
    if (scaffolds.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(
        tester.element(scaffolds.first),
      ).hideCurrentSnackBar();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          waterLogRepositoryProvider.overrideWithValue(waterRepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: LightRecordSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('饮水：快捷档位一键入账 → 累计刷新 → 撤销撤回（中文）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    await pumpSection(tester);

    // 初始：累计 0 / 目标 2000ml 标注 + 三个快捷档位。
    expect(find.text('今日饮水'), findsOneWidget);
    expect(find.text('0 / 2000 毫升'), findsOneWidget);
    expect(find.text('+200'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget);
    expect(find.text('+500'), findsOneWidget);

    // 一键入账：累计即时刷新 +「已记录·撤销」吐司（D-11）。
    await tester.tap(find.text('+200'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('200 / 2000 毫升'), findsOneWidget);
    expect(find.text('已记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // 撤销 → 记录撤回，累计回落。
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('0 / 2000 毫升'), findsOneWidget);
    expect(await waterRepo.totalForDate(todayKey()), 0);

    // 连续入账：累计叠加（新吐司顶替旧吐司，动画过渡约 500ms）。
    await tester.tap(find.text('+200'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('+500'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('700 / 2000 毫升'), findsOneWidget);
    expect(await waterRepo.totalForDate(todayKey()), 700);

    await settleUi(tester);
  });

  testWidgets('体重：输入校验 → 保存 → 同日覆写取最新（中文）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    await pumpSection(tester);

    // 初始未记录。
    expect(find.text('体重'), findsOneWidget);
    expect(find.text('记一下'), findsOneWidget);

    // 打开录入对话框（48px 输入 + 绿 focus 由主题保障）。
    await tester.tap(find.text('体重'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('记录今日体重'), findsOneWidget);
    expect(find.text('体重（千克）'), findsOneWidget);

    // 非数字 → 校验错误，不落库。
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    expect(find.text('请输入 20 到 300 之间的数'), findsOneWidget);
    expect(weightStore.loadRange(todayKey(), todayKey()), isEmpty);

    // 超出合理区间 → 校验错误。
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    expect(find.text('请输入 20 到 300 之间的数'), findsOneWidget);

    // 合法值 → 保存成功（一位小数），对话框关闭，卡片展示。
    await tester.enterText(find.byType(TextField), '65.5');
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('记录今日体重'), findsNothing);
    expect(find.text('65.5 千克'), findsOneWidget);
    expect(weightStore.loadRange(todayKey(), todayKey())[todayKey()], 65.5);

    // 同日重复记 → 覆写取最新。
    await tester.tap(find.text('体重'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '70');
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('70.0 千克'), findsOneWidget);
    expect(weightStore.loadRange(todayKey(), todayKey())[todayKey()], 70.0);

    await settleUi(tester);
  });

  testWidgets('双语：英文环境饮水 / 体重文案与校验（英文）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpSection(tester);

    expect(find.text('Water today'), findsOneWidget);
    expect(find.text('0 / 2000 ml'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);

    // 饮水快捷档位（英文累计）。
    await tester.tap(find.text('+300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('300 / 2000 ml'), findsOneWidget);

    // 体重对话框英文校验 + 保存（单位仅 kg）。
    await tester.tap(find.text('Weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Log today's weight"), findsOneWidget);
    expect(find.text('Weight (kg)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Log it'));
    await tester.pump();
    expect(find.text('Enter a value between 20 and 300'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '180');
    await tester.tap(find.widgetWithText(FilledButton, 'Log it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('180.0 kg'), findsOneWidget);
    expect(weightStore.loadRange(todayKey(), todayKey())[todayKey()], 180.0);

    await LocaleSettings.setLocale(AppLocale.zhCn);
    await settleUi(tester);
  });
}

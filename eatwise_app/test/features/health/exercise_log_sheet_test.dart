import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/presentation/exercise_log_sheet.dart';
import 'package:eatwise/features/health/presentation/health_widgets.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记运动 widget 测试：弹层（类型 chips / 时长 / 实时预估 kcal / 覆盖 /
/// 校验 / 今日列表删除）+ 保存与 D-11 撤销 + 数据页消耗卡合并与
/// unsupported 步数「—」引导。
void main() {
  late AppDatabase db;
  late ExerciseLogRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.memory();
    repo = ExerciseLogRepository(db: db);
    addTearDown(() async => db.close());
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  String todayKey() => localDateKey(DateTime.now());

  /// 测试收尾：隐藏吐司（取消时长 Timer）→ 卸载并多次 pump（drift 流退订
  /// 经 `Timer.run` 清理，须冲刷假时钟区，同 light_record_section_test）。
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

  Future<void> pumpEntry(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseLogRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () => startExerciseLog(context, ref),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('弹层：类型/时长 → 实时预估 kcal（60kg 兜底标注）→ 保存 → 撤销', (tester) async {
    await pumpEntry(tester);
    await openSheet(tester);

    // 弹层要素：标题 / 类型 chips / 时长与消耗输入 / 60kg 估算标注。
    expect(find.text('记运动'), findsOneWidget);
    expect(find.text('走路'), findsOneWidget);
    expect(find.text('HIIT'), findsOneWidget);
    expect(find.text('未填体重，按 60 千克估算'), findsOneWidget);

    // 默认走路（MET 3.5），30 分钟 → 3.5 × 60 × 0.5 = 105 kcal。
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise.duration')),
      '30',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('exercise.kcal')),
          )
          .controller!
          .text,
      '105',
    );

    // 保存 → 弹层关闭 +「已记录·撤销」吐司（D-11）。
    await tester.tap(find.byKey(const ValueKey<String>('exercise.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    final saved = await repo.logsForDate(todayKey());
    expect(saved, hasLength(1));
    expect(saved.single.typeKey, 'walk');
    expect(saved.single.durationMin, 30);
    expect(saved.single.kcal, 105);

    // 撤销 → 物理删除，合计回落。
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已撤销'), findsOneWidget);
    expect(await repo.totalKcalForDate(todayKey()), 0);

    await settleUi(tester);
  });

  testWidgets('弹层：走路按步数录入 —— 自动换算热量，时长可留空，步数落库', (tester) async {
    await pumpEntry(tester);
    await openSheet(tester);

    // 默认走路 → 步数字段可见；1466 步 60kg ≈ 68 kcal（1.036 口径）。
    expect(
      find.byKey(const ValueKey<String>('exercise.steps')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise.steps')),
      '1466',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('exercise.kcal')),
          )
          .controller!
          .text,
      '68',
    );

    // 时长留空直接保存（步数口径无时长要求）→ 步数随记录落库。
    await tester.tap(find.byKey(const ValueKey<String>('exercise.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final saved = (await repo.logsForDate(todayKey())).single;
    expect(saved.typeKey, 'walk');
    expect(saved.steps, 1466);
    expect(saved.durationMin, 0);
    expect(saved.kcal, 68);

    // 重开弹层：今日列表显示「走路 · 1466 步 · 68 千卡」（不出「0 分钟」）。
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('走路 · 1466 步 · 68 千卡'), findsOneWidget);
    expect(find.textContaining('0 分钟'), findsNothing);

    // 切到慢跑 → 步数字段隐藏（仅走路可录步数）。
    await tester.tap(find.text('慢跑'));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('exercise.steps')), findsNothing);

    await settleUi(tester);
  });

  testWidgets('弹层：kcal 手改覆盖后不再随类型联动；校验非法时长', (tester) async {
    await pumpEntry(tester);
    await openSheet(tester);

    // 时长为空直接保存 → 校验错误，不落库。
    await tester.tap(find.byKey(const ValueKey<String>('exercise.save')));
    await tester.pump();
    expect(find.text('请输入大于 0 的分钟数'), findsOneWidget);
    expect(await repo.logsForDate(todayKey()), isEmpty);

    // 慢跑 30 分钟 → 7.0 × 60 × 0.5 = 210 kcal。
    await tester.tap(find.text('慢跑'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise.duration')),
      '30',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('exercise.kcal')),
          )
          .controller!
          .text,
      '210',
    );

    // 手改覆盖为 250 → 切类型不再联动重算。
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise.kcal')),
      '250',
    );
    await tester.pump();
    await tester.tap(find.text('瑜伽'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('exercise.kcal')),
          )
          .controller!
          .text,
      '250',
    );

    await tester.tap(find.byKey(const ValueKey<String>('exercise.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final saved = await repo.logsForDate(todayKey());
    expect(saved.single.typeKey, 'yoga');
    expect(saved.single.kcal, 250);

    await settleUi(tester);
  });

  testWidgets('弹层：今日运动列表展示并可删（已删除吐司）', (tester) async {
    await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    await pumpEntry(tester);
    await openSheet(tester);

    expect(find.text('今日运动'), findsOneWidget);
    expect(find.text('慢跑 · 30 分钟 · 210 千卡'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已删除'), findsOneWidget);
    expect(await repo.logsForDate(todayKey()), isEmpty);

    await settleUi(tester);
  });

  testWidgets('弹层：档案体重 80kg → 按档案估算且无兜底标注（英文）', (tester) async {
    SharedPreferencesOnboardingStore(
      prefs,
    ).saveProfile(const OnboardingProfile(weightKg: 80));
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpEntry(tester);
    await openSheet(tester);

    expect(find.text('Log exercise'), findsOneWidget);
    expect(find.text('Weight not set — estimated with 60 kg'), findsNothing);

    // Walking 3.5 × 80 × 0.5 = 140 kcal。
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise.duration')),
      '30',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('exercise.kcal')),
          )
          .controller!
          .text,
      '140',
    );

    await tester.tap(find.byKey(const ValueKey<String>('exercise.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Logged'), findsOneWidget);
    expect((await repo.logsForDate(todayKey())).single.kcal, 140);

    await LocaleSettings.setLocale(AppLocale.zhCn);
    await settleUi(tester);
  });

  group('数据页消耗卡（合并 + unsupported）', () {
    Future<void> pumpBurnCard(
      WidgetTester tester, {
      int? steps,
      double? burnKcal,
      bool estimated = false,
      String? stepsGuide,
    }) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: TodayBurnCard(
                steps: steps,
                burnKcal: burnKcal,
                estimated: estimated,
                burnGoalKcal: 300,
                stepsGoal: 8000,
                stepsGuide: stepsGuide,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('系统 + 手动合并值出目标环进度（430/300 → 封顶 100%）', (tester) async {
      await pumpBurnCard(tester, steps: 8000, burnKcal: 430);

      expect(find.text('8000'), findsOneWidget);
      expect(find.text('430 kcal'), findsOneWidget);
      expect(find.text('430 / 300 千卡'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // 有步数 → 不出「—」与引导文案。
      expect(find.text('—'), findsNothing);

      await settleUi(tester);
    });

    testWidgets('unsupported：步数「—」+ 引导文案「手动记运动可计入消耗」，消耗仅手动合计', (tester) async {
      await pumpBurnCard(tester, burnKcal: 180, stepsGuide: '手动记运动可计入消耗');

      expect(find.text('—'), findsOneWidget);
      expect(find.text('手动记运动可计入消耗'), findsOneWidget);
      expect(find.text('180 kcal'), findsOneWidget);
      // 180 / 300 → 60%。
      expect(find.text('60%'), findsOneWidget);

      await settleUi(tester);
    });
  });
}

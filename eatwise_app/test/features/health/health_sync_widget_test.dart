import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/data/health_gateway.dart';
import 'package:eatwise/features/health/presentation/health_sync_section.dart';
import 'package:eatwise/features/health/presentation/health_widgets.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _FakeHealthGateway implements HealthGateway {
  bool supported = true;
  bool granted = false;
  bool grantResult = true;
  bool revoked = false;
  int? steps = 6200;
  double? activeEnergyKcal = 245;
  double? weightKg = 66.5;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasAuthorization() async => granted;

  @override
  Future<bool> requestAuthorization() async {
    granted = grantResult;
    return grantResult;
  }

  @override
  Future<void> revokeAuthorization() async {
    revoked = true;
    granted = false;
  }

  @override
  Future<int?> getTodaySteps(DateTime now) async => steps;

  @override
  Future<double?> getTodayActiveEnergyKcal(DateTime now) async =>
      activeEnergyKcal;

  @override
  Future<double?> getLatestWeightKg(DateTime now) async => weightKg;
}

/// 阶段 D widget 覆盖：设置页「运动数据」区块（单独同意弹窗、开关状态机、
/// 今日预览、一键填入体重记录）与数据页「今日消耗」卡渲染。
void main() {
  late SharedPreferences prefs;
  late InMemoryExerciseSyncConsentStore consentStore;
  late _FakeHealthGateway gateway;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    consentStore = InMemoryExerciseSyncConsentStore();
    gateway = _FakeHealthGateway();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            exerciseSyncConsentStoreProvider.overrideWithValue(consentStore),
            healthGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: HealthSyncSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Switch syncSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch));

  testWidgets('开启前弹单独同意；暂不同意 → 不开关、不落同意', (tester) async {
    await pumpSection(tester);
    expect(syncSwitch(tester).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // 单独同意弹窗（GDPR Art.9）：范围/用途/本地处理/可撤回四要素。
    expect(find.text('开启运动数据同步？'), findsOneWidget);
    expect(find.textContaining('不会上传到服务器'), findsOneWidget);

    await tester.tap(find.text('暂不同意'));
    await tester.pumpAndSettle();
    expect(syncSwitch(tester).value, isFalse);
    expect(consentStore.consented, isFalse);
  });

  testWidgets('同意并开启 → 已授权 + 今日预览（步数/消耗/体重）', (tester) async {
    await pumpSection(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并开启'));
    await tester.pumpAndSettle();

    expect(consentStore.consented, isTrue);
    expect(syncSwitch(tester).value, isTrue);
    expect(find.text('已授权'), findsOneWidget);
    expect(find.textContaining('步数 6200'), findsOneWidget);
    expect(find.textContaining('活动消耗 245 kcal'), findsOneWidget);
    expect(find.textContaining('最新体重 66.5 kg'), findsOneWidget);
  });

  testWidgets('设备不支持 → 状态行明示', (tester) async {
    gateway.supported = false;
    await pumpSection(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并开启'));
    await tester.pumpAndSettle();

    expect(find.textContaining('设备不支持'), findsOneWidget);
  });

  testWidgets('一键填入体重记录：写 WeightLogStore 今日条目', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并开启'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('填入今日体重记录'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HealthSyncSection)),
    );
    final stored = container.read(weightLogStoreProvider).loadRange(date, date);
    expect(stored[date], closeTo(66.5, 0.001));
    expect(find.textContaining('已填入今日体重记录'), findsOneWidget);
  });

  testWidgets('关闭同步：撤销授权 + 清同意 + 提示', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并开启'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(gateway.revoked, isTrue);
    expect(consentStore.consented, isFalse);
    expect(syncSwitch(tester).value, isFalse);
    expect(find.textContaining('已关闭运动数据同步'), findsOneWidget);
  });

  group('TodayBurnCard（数据页今日消耗卡）', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      int? steps = 6200,
      double? burnKcal = 245,
      bool estimated = false,
      double? intakeKcal = 1500,
      double? burnGoalKcal,
      int? stepsGoal,
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
                intakeKcal: intakeKcal,
                burnGoalKcal: burnGoalKcal,
                stepsGoal: stepsGoal,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('活动能量 + 步数 + 结余（摄入−消耗）', (tester) async {
      await pumpCard(tester);
      expect(find.text('今日消耗'), findsOneWidget);
      expect(find.text('245 kcal'), findsOneWidget);
      expect(find.text('6200'), findsOneWidget);
      expect(find.textContaining('+1255'), findsOneWidget);
    });

    testWidgets('步数粗估兜底时标注估算', (tester) async {
      await pumpCard(tester, burnKcal: 120, estimated: true);
      expect(find.textContaining('按步数估算'), findsOneWidget);
    });

    testWidgets('当日无摄入记录 → 不出结余行', (tester) async {
      await pumpCard(tester, intakeKcal: null);
      expect(find.textContaining('结余'), findsNothing);
    });

    testWidgets('英文渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpCard(tester);
      expect(find.text("Today's burn"), findsOneWidget);
      expect(find.textContaining('+1255'), findsOneWidget);
    });

    testWidgets('薄荷走查 P2：消耗目标环（X/目标 Y）+ 步数进度行', (tester) async {
      await pumpCard(tester, burnKcal: 100, burnGoalKcal: 200, stepsGoal: 5000);
      // 环中心百分比 + 环下 X/目标 千卡。
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('100 / 200 千卡'), findsOneWidget);
      // 步数目标进度文本行。
      expect(find.text('6200 / 5000 步'), findsOneWidget);
    });

    testWidgets('超目标：弧封顶 100%，文案展示真实 X/目标', (tester) async {
      await pumpCard(tester, burnGoalKcal: 200);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('245 / 200 千卡'), findsOneWidget);
    });

    testWidgets('无目标参数 → 保持原布局（无环无进度行）', (tester) async {
      await pumpCard(tester);
      expect(
        find.descendant(
          of: find.byType(TodayBurnCard),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('英文目标环渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpCard(tester, burnKcal: 100, burnGoalKcal: 200, stepsGoal: 5000);
      expect(find.text('100 / 200 kcal'), findsOneWidget);
      expect(find.text('6200 / 5000 steps'), findsOneWidget);
    });
  });

  group('每日目标设置（薄荷走查 P2）', () {
    testWidgets('运动数据区块展示默认目标（200 千卡 / 5000 步）', (tester) async {
      await pumpSection(tester);
      expect(find.text('每日消耗目标'), findsOneWidget);
      expect(find.text('200 千卡'), findsOneWidget);
      expect(find.text('每日步数目标'), findsOneWidget);
      expect(find.text('5000 步'), findsOneWidget);
    });

    testWidgets('修改步数目标：即时生效并持久化', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('每日步数目标'));
      await tester.pumpAndSettle();

      expect(find.text('设置每日步数目标'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '8000');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('8000 步'), findsOneWidget);
      expect(prefs.getInt('health.stepsGoal.v1'), 8000);
    });

    testWidgets('修改消耗目标：即时生效并持久化', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('每日消耗目标'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '350');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('350 千卡'), findsOneWidget);
      expect(prefs.getDouble('health.burnGoalKcal.v1'), 350);
    });

    testWidgets('越界输入：行内报错不落盘', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('每日步数目标'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '100');
      await tester.tap(find.text('确定'));
      await tester.pump();

      expect(find.text('请输入范围内的有效数值'), findsOneWidget);
      expect(prefs.getInt('health.stepsGoal.v1'), isNull);
      // 关闭弹窗后仍是默认值。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('5000 步'), findsOneWidget);
    });
  });
}

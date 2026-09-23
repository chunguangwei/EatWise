import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/app_bottom_sheet.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/domain/exercise_screenshot_logic.dart';
import 'package:eatwise/features/health/presentation/exercise_screenshot_flow.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/presentation/window_editor_sheet.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_meal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹层按钮常驻钉死测试（真机走查：华为 1080x2440 + 大字体 + 键盘弹起，
/// 「确认记录」被顶出屏幕只露绿边）。统一三条件：360x640 逻辑像素 +
/// textScaler 1.3 + 键盘 viewInsets 300——动作按钮必须完整落在屏内且可点。
void main() {
  const screen = Size(360, 640);

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  /// 断言按钮完整落在 360x640 屏内（右/下不越界，顶部不被挤出）。
  void expectButtonOnScreen(WidgetTester tester, Finder button) {
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
  }

  /// 三条件泵入：小屏 + 大字体 + 模拟键盘。
  Future<void> pumpSmall(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const <Override>[],
    bool keyboard = true,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (keyboard) {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
    }
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(body: home),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const goal = NutritionGoal(
    bmr: null,
    tdee: null,
    targetKcal: 2000,
    proteinG: 125,
    carbG: 225,
    fatG: 67,
    usedFallback: true,
    configVersion: '1.0.0',
  );

  const food = Food(
    id: 'f-beef',
    nameZh: '牛肉干',
    nameEn: 'Beef Jerky',
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 550,
    proteinPer100g: 45.6,
    carbPer100g: 1.8,
    fatPer100g: 40.2,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: '',
    contributionStatus: null,
  );

  testWidgets('AppBottomSheet 骨架：超高内容封顶内滚，动作按钮常驻且可点', (tester) async {
    var tapped = 0;
    await pumpSmall(
      tester,
      AppBottomSheet(
        bottomBar: FilledButton(
          onPressed: () => tapped++,
          child: const Text('确认'),
        ),
        content: Column(
          children: <Widget>[for (var i = 0; i < 30; i++) Text('内容行 $i')],
        ),
      ),
    );

    // 按钮完整在屏内，点击生效。
    expectButtonOnScreen(tester, find.widgetWithText(FilledButton, '确认'));
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    expect(tapped, 1);
    // 内容区内部滚动：首行可见，末行可滚到（scrollable 存在且有滚动余量）。
    expect(find.text('内容行 0'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('食物详情弹层：牛肉干高热量行不横向溢出，确认记录按钮在屏内', (tester) async {
    var confirmed = '';
    await pumpSmall(
      tester,
      FoodDetailSheet(food: food, onConfirm: (text) => confirmed = text),
      overrides: <Override>[nutritionGoalProvider.overrideWithValue(goal)],
    );

    // 横向溢出在 flutter_test 中即异常——通过即无溢出（千卡/千焦行已修）。
    final confirm = find.widgetWithText(FilledButton, '确认记录');
    expectButtonOnScreen(tester, confirm);
    // 输入份量出现四格预览后再断言一次（内容更高场景）。
    await tester.enterText(find.byType(TextField), '50');
    await tester.pump();
    expectButtonOnScreen(tester, confirm);
    await tester.tap(confirm);
    expect(confirmed, '50');
  });

  testWidgets('拍照明细确认弹层：12 条明细 + 键盘，全部记录按钮在屏内', (tester) async {
    final items = <RecognizedMealItem>[
      for (var i = 0; i < 12; i++)
        RecognizedMealItem(
          name: '米饭 $i',
          grams: 100,
          per100g: const NutritionSnapshot(
            kcal: 116,
            proteinG: 2.6,
            carbG: 25.9,
            fatG: 0.3,
          ),
          confidence: 0.9,
          food: food,
        ),
    ];
    await pumpSmall(tester, PhotoMealConfirmSheet(items: items));

    expectButtonOnScreen(tester, find.widgetWithText(FilledButton, '全部记录'));
  });

  testWidgets('运动截图确认弹层：汇总字段 + 键盘，确认记录按钮在屏内', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.memory();
    addTearDown(() async => db.close());
    await pumpSmall(
      tester,
      const ExerciseScreenshotConfirmSheet(
        data: ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.summary,
          steps: 8000,
          floorsClimbedM: 20,
          activeCaloriesKcal: 320,
        ),
      ),
      overrides: <Override>[
        exerciseLogRepositoryProvider.overrideWithValue(
          ExerciseLogRepository(db: db),
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

    expectButtonOnScreen(
      tester,
      find.byKey(const ValueKey<String>('screenshot.save')),
    );
  });

  testWidgets('断食窗口编辑弹层：小屏大字体键盘，确定按钮在屏内且可点', (tester) async {
    await pumpSmall(
      tester,
      const WindowEditorSheet(initialEatingHours: 8, initialStartMinutes: 720),
    );

    final confirm = find.byKey(
      const ValueKey<String>('fasting.windowEditor.confirm'),
    );
    expectButtonOnScreen(tester, confirm);
    await tester.tap(confirm);
    await tester.pump();
  });
}

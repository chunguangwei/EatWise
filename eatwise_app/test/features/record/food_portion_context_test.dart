import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = Food(
  id: 'rice',
  nameZh: '米饭',
  nameEn: 'Rice',
  aliasesZh: '[]',
  aliasesEn: '[]',
  kcalPer100g: 116,
  proteinPer100g: 2.6,
  carbPer100g: 25.9,
  fatPer100g: 0.3,
  isCustom: false,
  source: 'manual',
  customSyncPending: false,
  customLocalVersion: 0,
  customClientRequestId: '',
  customSyncFailCount: 0,
  customSyncFailed: false,
);

NutritionGoal _goal(int targetKcal) => NutritionGoal(
  bmr: null,
  tdee: null,
  targetKcal: targetKcal,
  proteinG: 125,
  carbG: 225,
  fatG: 67,
  usedFallback: true,
  configVersion: '1.0.0',
);

Future<void> _pump(
  WidgetTester tester, {
  Food food = _food,
  int targetKcal = 2000,
  AppLocale locale = AppLocale.zhCn,
  ThemeData? theme,
  double keyboardInset = 0,
}) async {
  LocaleSettings.setLocaleSync(locale);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionGoalProvider.overrideWithValue(_goal(targetKcal)),
        userMeProvider.overrideWith((ref) => Future<UserMeView?>.value()),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
            child: child!,
          ),
          home: Scaffold(
            body: FoodDetailSheet(food: food, onConfirm: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.zhCn));

  testWidgets('未填份量显示输入提示与真实来源，不评价食物或折算抵消步数', (tester) async {
    await _pump(tester);
    expect(find.text('数据来源：食物库'), findsOneWidget);
    expect(find.text('输入份量，查看本份占每日热量目标的比例'), findsOneWidget);
    expect(find.textContaining('放心吃'), findsNothing);
    expect(find.textContaining('大约需走'), findsNothing);
    expect(find.byKey(const ValueKey('foodDetail.portionShare')), findsNothing);
  });

  testWidgets('本份占比按输入份量实时变化；非法输入不回退为100克', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pump();
    expect(find.text('本份占每日热量目标 11.6%'), findsOneWidget);
    expect(find.text('本份 200 克 · 当前每日目标 2000 千卡'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pump();
    expect(find.text('本份占每日热量目标 5.8%'), findsOneWidget);
    for (final invalid in ['', '0', 'NaN', 'Infinity', '5000.1', '9' * 400]) {
      await tester.enterText(find.byType(TextField).first, invalid);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('foodDetail.portionShare')),
        findsNothing,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('目标缺失不除零、不展示虚构占比，合法份量仍可记录', (tester) async {
    await _pump(tester, targetKcal: 0);
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pump();
    expect(find.text('每日热量目标暂不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('foodDetail.portionShare')), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('占比超过100%仍如实展示，合法零热量显示0%', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pump();
    expect(find.text('本份占每日热量目标 290%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, food: _food.copyWith(kcalPer100g: 0));
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pump();
    expect(find.text('本份占每日热量目标 0%'), findsOneWidget);
  });

  for (final sample in <(Food, String)>[
    (_food.copyWith(isCustom: true), '数据来源：个人填写'),
    (
      _food.copyWith(isCustom: true, source: 'llm-estimate'),
      '数据来源：AI 估算，请核对数值',
    ),
    (_food.copyWith(source: 'community'), '数据来源：社区贡献'),
    (_food.copyWith(source: 'unrecognized'), '数据来源：暂未提供'),
    (_food.copyWith(nameZh: 'rice', nameEn: 'rice'), '数据来源：暂未提供'),
  ]) {
    testWidgets('来源说明只依赖已存字段：${sample.$2} / ${sample.$1.source}', (
      tester,
    ) async {
      await _pump(tester, food: sample.$1);
      expect(find.text(sample.$2), findsOneWidget);
    });
  }

  for (final source in ['cfct', 'usda-sr', 'manual']) {
    testWidgets('内置库纠错审核通过保留原始来源：$source', (tester) async {
      await _pump(
        tester,
        food: _food.copyWith(
          source: source,
          contributionStatus: const Value('approved'),
        ),
      );
      expect(find.text('数据来源：食物库'), findsOneWidget);
      expect(find.text('数据来源：社区贡献'), findsNothing);
    });
  }

  for (final locale in [AppLocale.zhCn, AppLocale.en]) {
    for (final dark in [false, true]) {
      testWidgets('份量上下文 360×640 2倍字 300键盘 ${locale.name} dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          locale: locale,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          keyboardInset: 300,
        );
        await tester.enterText(find.byType(TextField).first, '200');
        await tester.pump();
        final share = find.byKey(const ValueKey('foodDetail.portionShare'));
        expect(share, findsOneWidget);
        await tester.ensureVisible(share);
        await tester.pump();
        expect(
          find.text(
            locale == AppLocale.en
                ? 'This portion is 11.6% of your daily calorie target'
                : '本份占每日热量目标 11.6%',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

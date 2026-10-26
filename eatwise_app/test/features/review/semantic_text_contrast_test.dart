import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/presentation/trend_section.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const food = Food(
    id: 'cf-contrast',
    nameZh: '自制餐点',
    nameEn: 'Homemade meal',
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 25.9,
    fatPer100g: 0.3,
    isCustom: true,
    source: 'manual',
    customSyncPending: false,
    customClientRequestId: 'contrast-request',
    customSyncFailCount: 0,
    customSyncFailed: false,
  );
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

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  // Read the rendered label and its actual tint/gradient, so a future return to
  // decorative text colors fails even when the theme tokens themselves pass.
  void expectReadable(WidgetTester tester, String label, Color underlay) {
    final finder = find.text(label);
    expect(finder, findsOneWidget);
    final foreground = tester.widget<Text>(finder).style!.color!;
    BoxDecoration? surface;
    tester.element(finder).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Container && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration! as BoxDecoration;
        if (decoration.color != null || decoration.gradient != null) {
          surface = decoration;
          return false;
        }
      }
      return true;
    });
    expect(surface, isNotNull);
    final background = Color.alphaBlend(
      surface!.color ?? Colors.transparent,
      underlay,
    );
    for (final color in surface!.gradient?.colors ?? <Color>[background]) {
      expect(
        contrastRatio(foreground, Color.alphaBlend(color, background)),
        greaterThanOrEqualTo(4.5),
        reason: 'Normal text "$label" must remain readable on its surface',
      );
    }
  }

  for (final dark in <bool>[false, true]) {
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    final colors = theme.extension<AppColors>()!;

    for (final (source, label) in <(String, String)>[
      ('manual', '数据来源：个人填写'),
      ('llm-estimate', '数据来源：AI 估算，请核对数值'),
      ('community', '数据来源：社区贡献'),
    ]) {
      testWidgets('食物详情来源与份量目标文字对比度 $label dark=$dark', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              nutritionGoalProvider.overrideWithValue(goal),
              userMeProvider.overrideWith((ref) => Future<UserMeView?>.value()),
            ],
            child: TranslationProvider(
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  backgroundColor: colors.bgSecondary,
                  body: FoodDetailSheet(
                    food: food.copyWith(source: source),
                    onConfirm: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expectReadable(tester, label, colors.bgSecondary);
        expectReadable(tester, '自定义', colors.bgSecondary);
        await tester.enterText(find.byType(TextField).first, '100');
        await tester.pump();
        expectReadable(tester, '本份占每日热量目标 5.8%', colors.bgSecondary);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('体重目标线说明文字对比度 dark=$dark', (tester) async {
      final now = DateTime(2026, 10, 25);
      final container = ProviderContainer(
        overrides: <Override>[
          reportsNowProvider.overrideWithValue(now),
          weightTargetProvider.overrideWithValue(60),
          weightRecordCountProvider.overrideWithValue(3),
          trendPointsProvider.overrideWithValue(<TrendPoint>[
            TrendPoint(
              start: now.subtract(const Duration(days: 1)),
              end: now.subtract(const Duration(days: 1)),
              value: 65,
              recordedDays: 1,
              totalDays: 1,
            ),
            TrendPoint(
              start: now,
              end: now,
              value: 64,
              recordedDays: 1,
              totalDays: 1,
            ),
          ]),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(reportDimensionProvider.notifier)
          .select(ReportDimension.weight);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TranslationProvider(
            child: MaterialApp(
              theme: theme,
              home: const Scaffold(
                body: SingleChildScrollView(child: ReportTrendSection()),
              ),
            ),
          ),
        ),
      );
      expectReadable(tester, '目标 60.0 公斤', colors.bgSecondary);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/metric_card.dart';
import 'package:eatwise/features/fasting/presentation/today_budget_row.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  void configureViewport(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('MetricCard wraps its label and scales extreme value with unit', (
    tester,
  ) async {
    configureViewport(tester, 2);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                child: MetricCard(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: Colors.deepOrange,
                  label: 'Daily energy consumption and activity',
                  value: '999+',
                  unit: 'kcal',
                  caption:
                      'An extremely long caption that should remain bounded',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final label = tester.widget<Text>(
      find.text('Daily energy consumption and activity'),
    );
    expect(label.maxLines, 2);
    expect(find.text('999+'), findsOneWidget);
    expect(find.text('kcal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpGrid(WidgetTester tester, double scale) async {
    configureViewport(tester, scale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          todayExerciseKcalProvider.overrideWith(
            (ref) => Stream<double>.value(999999),
          ),
          todayExerciseStepsProvider.overrideWith(
            (ref) => Stream<int>.value(999999),
          ),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 360, child: TodayMetricGrid()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final (scale, twoColumns) in <(double, bool)>[
    (1.0, true),
    (1.3, true),
    (2.0, false),
  ]) {
    testWidgets('TodayMetricGrid at 360px scale $scale stays overflow-free', (
      tester,
    ) async {
      await pumpGrid(tester, scale);

      final cards = find.byType(MetricCard);
      expect(cards, findsNWidgets(2));
      expect(find.text('999999'), findsNWidgets(2));
      final first = tester.getRect(cards.first);
      final second = tester.getRect(cards.last);
      if (twoColumns) {
        expect(second.top, closeTo(first.top, 1));
        expect(second.left, greaterThan(first.left));
      } else {
        expect(second.top, greaterThan(first.top));
        expect(second.left, closeTo(first.left, 1));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

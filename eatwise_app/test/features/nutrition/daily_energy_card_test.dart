import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/nutrition/presentation/daily_energy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/review_capture.dart';

void main() {
  setUpAll(loadReviewFont);
  for (final locale in [AppLocale.zhCn, AppLocale.en]) {
    for (final dark in [false, true]) {
      testWidgets('摄入目标卡 360dp 双倍字体 $locale dark=$dark', (tester) async {
        await LocaleSettings.setLocale(locale);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              theme: reviewTheme(dark ? AppTheme.dark() : AppTheme.light()),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: DailyEnergyCard(
                    intakeKcal: 1500,
                    targetKcal: 2000,
                    historical: false,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('1500 kcal'), findsOneWidget);
        expect(find.text('2000 kcal'), findsOneWidget);
        expect(
          find.text(
            locale == AppLocale.zhCn
                ? '距目标还差 500 kcal'
                : '500 kcal below target',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await captureReview(
          tester,
          'energy-${locale.languageCode}-${dark ? "dark" : "light"}',
        );
      });
    }
  }
  testWidgets('未记录不宣称摄入为零；历史目标标明当前基准', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: DailyEnergyCard(
              intakeKcal: null,
              targetKcal: 2000,
              historical: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('不能据此判断'), findsOneWidget);
    expect(find.textContaining('历史目标未保存'), findsOneWidget);
    expect(find.textContaining('距目标还差'), findsNothing);
  });
}

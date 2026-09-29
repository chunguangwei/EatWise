import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/nutrition/presentation/trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 近 7 日趋势图：断食 tab 三态（历史天有数据出图 / 全空空态引导）。
void main() {
  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Widget buildApp({List<double?>? kcal, List<double?>? fasting}) {
    return TranslationProvider(
      child: ProviderScope(
        overrides: <Override>[
          weeklyKcalProvider.overrideWith(
            (ref) => kcal ?? List<double?>.filled(7, null),
          ),
          weeklyFastingHoursProvider.overrideWith(
            (ref) => fasting ?? List<double?>.filled(7, null),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: TrendChartSection()),
          ),
        ),
      ),
    );
  }

  testWidgets('断食 tab：历史天有记录、当天未完成 → 历史天正常出图（非空态）', (tester) async {
    // 09-22~09-26 有断食时长，09-27/28（含今天，末位）无记录。
    await tester.pumpWidget(
      buildApp(fasting: <double?>[16, 15.5, null, 13, 14, null, null]),
    );
    await tester.pump();
    await tester.tap(find.text('断食时长'));
    await tester.pump();

    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsNothing);
    expect(find.text('去记录'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('断食 tab：近 7 日全空 → 空态引导文案 + 去记录 CTA', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.tap(find.text('断食时长'));
    await tester.pump();

    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsOneWidget);
    expect(find.text('去记录'), findsOneWidget);
  });

  testWidgets('热量 tab：历史天有记录即出图，不依赖当天是否记满', (tester) async {
    await tester.pumpWidget(
      buildApp(kcal: <double?>[1800, null, 2100, null, null, null, null]),
    );
    await tester.pump();

    expect(find.text('记满几天，趋势曲线就跑起来啦'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

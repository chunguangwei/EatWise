import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/nutrition/presentation/date_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('历史日期与回到今天在大字体小屏下不争抢空间', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.zhCn));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        nutritionNowProvider.overrideWithValue(DateTime(2026, 10, 25)),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectedDateProvider.notifier).prevDay();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: DateSwitcher(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final date = find.textContaining('10/24');
    expect(date, findsOneWidget);
    expect(tester.getSize(date).width, greaterThan(140));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(container.read(isTodaySelectedProvider), isTrue);
  });
}

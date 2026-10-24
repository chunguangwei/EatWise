import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:eatwise/features/streak/presentation/streak_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../social/social_test_fakes.dart';

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpCard(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const view = ServerStreakView(
      currentStreak: 1200,
      longestStreak: 1200,
      lastQualifiedDate: '2026-07-28',
      mendCardStock: 2,
      mendCardGrantsThisMonth: 2,
      mendCardExpiresAt: '2026-07-31',
      mendCardUsableWindowDays: 7,
      mendCardStatus: 'available',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          streakLocalStoreProvider.overrideWithValue(
            InMemoryStreakLocalStore(),
          ),
          streakApiProvider.overrideWithValue(FakeStreakApi(view: view)),
          streakTodayProvider.overrideWithValue(() => '2026-07-28'),
          currentUserIdProvider.overrideWithValue('anonymous'),
          analyticsClientsProvider.overrideWithValue(const []),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 360, child: StreakProfileCard()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  for (final scale in <double>[1.0, 1.3, 2.0]) {
    testWidgets('StreakProfileCard renders 999+ at 360px scale $scale', (
      tester,
    ) async {
      await pumpCard(tester, scale);

      expect(find.text('999+ days'), findsOneWidget);
      expect(find.text('1200 days'), findsOneWidget);
      final metricsRow = find.byWidgetPredicate((widget) {
        if (widget is! Row) return false;
        final row = find.byWidget(widget);
        bool contains(String text) => find
            .descendant(of: row, matching: find.text(text))
            .evaluate()
            .isNotEmpty;
        return contains('Current streak') &&
            contains('Longest streak') &&
            contains('Mend Cards');
      });
      expect(metricsRow, scale < 2.0 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

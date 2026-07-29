import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../fasting/presentation/fasting_presentation_test_helper.dart';
import '../fasting/tz_test_helper.dart';
import '../social/social_test_fakes.dart';

/// 首启隐私路由门禁（合规 §4.1）：未同意 → /legal/consent 拦截；
/// 同意后门禁翻转放行到首页；同意前协议正文（/legal/*）可读。
void main() {
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  late AppDatabase db;
  late SharedPreferences prefs;
  late PrivacyGate privacyGate;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    db = AppDatabase.memory();
    privacyGate = PrivacyGate(agreed: false);
    addTearDown(() async {
      await db.close();
    });
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            onboardingGateProvider.overrideWithValue(
              OnboardingGate(completed: true),
            ),
            privacyGateProvider.overrideWithValue(privacyGate),
            appDatabaseProvider.overrideWithValue(db),
            localNotificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            socialApiProvider.overrideWithValue(FakeSocialApi()),
            fastingClockProvider.overrideWithValue(() => bjtUtc(28, 0)),
            deviceLocationProvider.overrideWithValue(bjt),
            // 同意事件 flush 不触网。
            analyticsClientsProvider.overrideWithValue(const []),
          ],
          child: EatWiseApp(
            gate: OnboardingGate(completed: true),
            privacyGate: privacyGate,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('未同意主政策 → 门禁拦截到 /legal/consent，首页不可达', (tester) async {
    await pumpApp(tester);

    // 门禁拦截：弹窗页渲染，首页计时页不出现。
    expect(find.text('欢迎使用 EatWise'), findsOneWidget);
    expect(find.text('断食中'), findsNothing);
    expect(find.text('同意并继续'), findsOneWidget);

    // 同意前协议正文可读（/legal/* 前缀放行）。
    await tester.tap(find.text('查看《隐私政策》全文'));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await unmount(tester);
  });

  testWidgets('同意后门禁翻转：放行到首页', (tester) async {
    await pumpApp(tester);
    expect(find.text('欢迎使用 EatWise'), findsOneWidget);

    await tester.tap(find.text('我已阅读并同意《用户协议》与《隐私政策》'));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 门禁翻转 → redirect 重算 → 首页。
    expect(find.text('断食中'), findsOneWidget);
    expect(privacyGate.agreed, isTrue);

    await unmount(tester);
  });
}

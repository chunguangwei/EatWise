import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
import 'package:eatwise/features/legal/presentation/legal_pages.dart';
import 'package:eatwise/features/legal/presentation/privacy_consent_page.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首启隐私弹窗（合规 §4.1）：双勾选逻辑、同意落盘、协议/免责入口、双语。
void main() {
  late SharedPreferences prefs;
  late PrivacyGate gate;
  late InMemoryPrivacyConsentStore store;
  late InMemoryConsentStore consentStore;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    gate = PrivacyGate(agreed: false);
    store = InMemoryPrivacyConsentStore();
    consentStore = InMemoryConsentStore();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpConsent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/legal/consent',
      routes: <RouteBase>[
        // 同意后的显式导航目标（占位页，断言离开授权页用）。
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('home-placeholder')),
        ),
        GoRoute(
          path: '/legal/consent',
          builder: (context, state) => const PrivacyConsentPage(),
        ),
        GoRoute(
          path: '/legal/privacy',
          builder: (context, state) {
            final t = Translations.of(context);
            return LegalDocumentPage(
              title: t.legal.privacyPolicy.title,
              body: t.legal.privacyPolicy.body,
            );
          },
        ),
        GoRoute(
          path: '/legal/agreement',
          builder: (context, state) {
            final t = Translations.of(context);
            return LegalDocumentPage(
              title: t.legal.userAgreement.title,
              body: t.legal.userAgreement.body,
            );
          },
        ),
        GoRoute(
          path: '/legal/disclaimer',
          builder: (context, state) => const DisclaimerPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            privacyGateProvider.overrideWithValue(gate),
            privacyConsentStoreProvider.overrideWithValue(store),
            consentStoreProvider.overrideWithValue(consentStore),
            // 测试环境屏蔽真实上报通道（授权事件 flush 不触网）。
            analyticsClientsProvider.overrideWithValue(const []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FilledButton agreeButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '同意并继续'),
    );
  }

  testWidgets('双勾选逻辑：主同意必勾，健康单独同意独立不捆绑', (tester) async {
    await pumpConsent(tester);

    // 初始：两项均未勾，主按钮不可用（无默认勾选，§4.1）。
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(agreeButton(tester).onPressed, isNull);

    // 仅勾健康数据单独同意 → 主按钮仍不可用（不能替代主同意）。
    await tester.tap(find.text('健康数据单独同意（可选）'));
    await tester.pump();
    expect(agreeButton(tester).onPressed, isNull);

    // 勾主同意 → 可用（健康同意不随之联动，分离勾选）。
    await tester.tap(find.text('我已阅读并同意《用户协议》与《隐私政策》'));
    await tester.pump();
    expect(agreeButton(tester).onPressed, isNotNull);
  });

  testWidgets('同意落盘：主同意翻转门禁，健康同意与埋点授权跟随', (tester) async {
    await pumpConsent(tester);

    await tester.tap(find.text('我已阅读并同意《用户协议》与《隐私政策》'));
    await tester.pump();
    await tester.tap(find.text('健康数据单独同意（可选）'));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    await tester.pump();

    expect(gate.agreed, isTrue);
    expect(store.hasAgreedCurrentPolicy, isTrue);
    expect(store.healthDataGranted, isTrue);
    expect(store.agreedAtEpochSec, isNotNull);
    // 埋点授权默认跟随主同意（弹窗完成前保持 suppressed）。
    expect(consentStore.analyticsGranted, isTrue);
  });

  testWidgets('同意后显式导航离开授权页（回归 R1：不依赖隐式 redirect）', (tester) async {
    await pumpConsent(tester);

    await tester.tap(find.text('我已阅读并同意《用户协议》与《隐私政策》'));
    await tester.pump();
    await tester.tap(find.text('健康数据单独同意（可选）'));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    // 授权页已卸载，路由推进到 '/'（真实路由表内由 redirect 再分流到
    // /login 或 /onboarding；此处仅断言发生了导航）。
    expect(find.byType(PrivacyConsentPage), findsNothing);
    expect(find.text('home-placeholder'), findsOneWidget);
  });

  testWidgets('仅主同意：健康数据单独同意保持拒绝，仍可继续', (tester) async {
    await pumpConsent(tester);

    await tester.tap(find.text('我已阅读并同意《用户协议》与《隐私政策》'));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    await tester.pump();

    expect(gate.agreed, isTrue);
    expect(store.healthDataGranted, isFalse);
    expect(consentStore.analyticsGranted, isTrue);
  });

  testWidgets('协议全文与特殊人群提示入口同意前可达', (tester) async {
    await pumpConsent(tester);

    await tester.tap(find.text('查看《隐私政策》全文'));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsWidgets);
    expect(find.textContaining('生效日期'), findsOneWidget);

    // 返回弹窗（门禁放行 /legal/* 前缀）。
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看《用户协议》全文'));
    await tester.pumpAndSettle();
    expect(find.text('用户协议'), findsWidgets);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看不适宜断食人群提示'));
    await tester.pumpAndSettle();
    expect(find.text('特殊人群提示'), findsWidgets);
    expect(find.textContaining('孕期及哺乳期女性'), findsOneWidget);
  });

  testWidgets('英文渲染（双语，D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpConsent(tester);

    expect(find.text('Welcome to EatWise'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Agree and continue'), 120);
    await tester.pump();
    expect(find.text('Agree and continue'), findsOneWidget);
    expect(
      find.text('Separate consent for health data (optional)'),
      findsOneWidget,
    );
  });

  group('PrivacyConsentStore 持久化', () {
    test('SharedPreferences 实现：缺省未同意，同意落盘可重读', () async {
      final store = SharedPreferencesPrivacyConsentStore(prefs);
      expect(store.hasAgreedCurrentPolicy, isFalse);
      expect(store.healthDataGranted, isFalse);

      await store.agree(healthDataGranted: true);
      final reread = SharedPreferencesPrivacyConsentStore(prefs);
      expect(reread.hasAgreedCurrentPolicy, isTrue);
      expect(reread.healthDataGranted, isTrue);
      expect(reread.agreedAtEpochSec, isNotNull);

      await reread.setHealthDataGranted(false);
      expect(reread.healthDataGranted, isFalse);
    });

    test('埋点授权缺省 false：弹窗完成前 AnalyticsService 保持 suppressed', () {
      expect(SharedPreferencesConsentStore(prefs).analyticsGranted, isFalse);
      expect(InMemoryConsentStore().analyticsGranted, isFalse);
    });
  });
}

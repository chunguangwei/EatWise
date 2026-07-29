import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
import 'package:eatwise/features/legal/presentation/legal_pages.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

/// 设置页（M7 + 合规 D-18）：分组渲染、语言/主题切换即时生效、
/// 健康数据授权撤回、数据分析授权接 ConsentStore、导出/删除 stub 流程、双语。
void main() {
  late SharedPreferences prefs;
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;
  late InMemoryPrivacyConsentStore privacyStore;
  late InMemoryConsentStore consentStore;
  late _FakeExportService exportService;
  late _FakeDeletionService deletionService;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    adapter = FakeHttpAdapter();
    authGate = AuthGate()..loggedIn = true;
    tokenStore = InMemoryTokenStore();
    privacyStore = InMemoryPrivacyConsentStore()..hasAgreedCurrentPolicy = true;
    consentStore = InMemoryConsentStore();
    exportService = _FakeExportService();
    deletionService = _FakeDeletionService();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile',
          builder: (context, state) => const SettingsPage(),
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
    late ProviderContainer container;
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            privacyConsentStoreProvider.overrideWithValue(privacyStore),
            privacyGateProvider.overrideWithValue(PrivacyGate(agreed: true)),
            consentStoreProvider.overrideWithValue(consentStore),
            analyticsClientsProvider.overrideWithValue(const []),
            tokenStoreProvider.overrideWithValue(tokenStore),
            authGateProvider.overrideWithValue(authGate),
            apiDioProvider.overrideWith((ref) {
              final dio = createApiDio(
                config: ApiConfig(),
                tokenStore: tokenStore,
              );
              dio.httpClientAdapter = adapter;
              dio.interceptors
                      .whereType<AuthInterceptor>()
                      .single
                      .refreshDio
                      .httpClientAdapter =
                  adapter;
              return dio;
            }),
            dataExportServiceProvider.overrideWithValue(exportService),
            accountDeletionServiceProvider.overrideWithValue(deletionService),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120);
    await tester.pump();
  }

  testWidgets('分组渲染：账号/隐私/偏好/提醒/关于与关键行齐备', (tester) async {
    await pumpSettings(tester);

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('隐私'), findsOneWidget);
    expect(find.text('偏好'), findsOneWidget);
    expect(find.text('删除账号'), findsOneWidget);
    expect(find.text('导出我的数据'), findsOneWidget);
    expect(find.text('健康数据授权'), findsOneWidget);
    expect(find.text('数据分析授权'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    await scrollTo(tester, find.text('免责声明与特殊人群提示'));
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('通知设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('语言切换即时生效并持久化（D-15）', (tester) async {
    await pumpSettings(tester);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('语言'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 全树文案立即切英文，无需重启。
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(prefs.getString('settings.languageMode'), 'en');

    await unmount(tester);
  });

  testWidgets('主题切换即时生效并持久化（亮/暗/跟随系统）', (tester) async {
    final container = await pumpSettings(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.text('主题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('深色'));
    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(prefs.getString('settings.themeMode'), 'dark');

    await unmount(tester);
  });

  testWidgets('数据分析授权开关接 ConsentStore：授权采集、撤回 suppressed', (tester) async {
    await pumpSettings(tester);
    expect(consentStore.analyticsGranted, isFalse);

    // 两个 Switch：①健康数据授权 ②数据分析授权。
    final analyticsSwitch = find.byType(Switch).at(1);
    await tester.tap(analyticsSwitch);
    await tester.pump();
    await tester.pump();
    expect(consentStore.analyticsGranted, isTrue);

    // 撤回 → 停止采集（ConsentStore 回落 false）。
    await tester.tap(analyticsSwitch);
    await tester.pump();
    await tester.pump();
    expect(consentStore.analyticsGranted, isFalse);

    await unmount(tester);
  });

  testWidgets('撤回健康数据单独授权（§4.4）', (tester) async {
    privacyStore.healthDataGranted = true;
    await pumpSettings(tester);

    final healthSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(healthSwitch).value, isTrue);

    await tester.tap(healthSwitch);
    await tester.pump();
    await tester.pump();
    expect(privacyStore.healthDataGranted, isFalse);
    expect(find.textContaining('已撤回健康数据授权'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('导出数据走 stub：生成 JSON 占位并提示标注', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('导出我的数据'));
    await tester.pump();
    await tester.pump();
    expect(exportService.calls, 1);
    expect(find.textContaining('服务端导出（U3/U4）尚未实现'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('删除账号：7 天冷静期确认 → stub 申请 → 登出', (tester) async {
    adapter.stub('/auth/logout', StubResponse.json(200, <String, Object?>{}));
    await pumpSettings(tester);

    await tester.tap(find.text('删除账号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 确认弹窗明示后果与冷静期。
    expect(find.textContaining('7 天冷静期'), findsOneWidget);

    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(deletionService.calls, 1);
    expect(authGate.loggedIn, isFalse);
    expect(find.textContaining('删除申请已提交'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('隐私协议入口：查看隐私政策全文', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('隐私政策'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('生效日期'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('英文渲染（双语，D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Export my data'), findsOneWidget);

    await unmount(tester);
  });
}

class _FakeExportService implements DataExportService {
  int calls = 0;

  @override
  Future<String> requestExport() async {
    calls++;
    return '/tmp/eatwise_data_export_stub.json';
  }
}

class _FakeDeletionService implements AccountDeletionService {
  int calls = 0;

  @override
  Future<void> requestDeletion() async {
    calls++;
  }
}

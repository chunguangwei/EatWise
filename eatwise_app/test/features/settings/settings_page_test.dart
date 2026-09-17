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
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:eatwise/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

/// 设置页（M7 + 合规 D-18）：分组渲染、语言/主题切换即时生效、
/// 健康数据授权撤回、数据分析授权接 ConsentStore、U3 导出 / U5 删除 /
/// U6 撤销 / U1 脱敏手机号、双语。
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

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    List<Override> extraOverrides = const <Override>[],
  }) async {
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
            ...extraOverrides,
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
    expect(find.text('删除账号'), findsOneWidget);
    expect(find.text('身体档案'), findsOneWidget); // 阶段 A 新增入口（账号组）
    expect(find.text('导出我的数据'), findsOneWidget);
    expect(find.text('健康数据授权'), findsOneWidget);
    expect(find.text('数据分析授权'), findsOneWidget);

    // 账号区新增「身体档案」行后偏好组落在视口外，先滚动到可见。
    await scrollTo(tester, find.text('偏好'));
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

    // 账号区新增行后语言行可能落在视口外，先滚动到可见。
    await scrollTo(tester, find.text('语言'));
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
    // 账号区新增「修改密码」行后主题行落在视口外，先滚动到可见。
    await scrollTo(tester, find.text('主题'));
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

  testWidgets('导出数据走 U3：返回服务端聚合 JSON 保存路径并提示', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('导出我的数据'));
    await tester.pump();
    await tester.pump();
    expect(exportService.calls, 1);
    expect(find.textContaining('数据已导出'), findsOneWidget);
    expect(
      find.textContaining('/tmp/eatwise_data_export_20260729.json'),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('删除账号：确认 → U5 申请 → 冷静期弹窗显示截止日期 → 登出', (tester) async {
    adapter.stub('/auth/logout', StubResponse.json(200, <String, Object?>{}));
    await pumpSettings(tester);

    await tester.tap(find.text('删除账号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 确认弹窗明示后果与冷静期。
    expect(find.textContaining('7 天冷静期'), findsOneWidget);

    await tester.tap(find.text('确认删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deletionService.calls, 1);
    // 冷静期弹窗：显示截止日期与「重新登录即可撤销」。
    expect(find.textContaining('重新登录即可撤销'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(authGate.loggedIn, isFalse);
    expect(find.textContaining('删除申请已提交'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('账号区显示 U1 脱敏手机号', (tester) async {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{
            'id': 'u-1',
            'phone': '+8613****8000',
            'deletionStatus': null,
            'scheduledDeletionAt': null,
          },
        }),
      ),
    );
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('+8613****8000'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('冷静期内账号：显示删除预约状态，撤销（U6）后提示并刷新', (tester) async {
    Map<String, Object?> meEnvelope(String? status) {
      return StubResponse.envelope(<String, Object?>{
        'user': <String, Object?>{
          'id': 'u-1',
          'phone': '+8613****8000',
          'deletionStatus': status,
          'scheduledDeletionAt': status == 'pending'
              ? DateTime.now()
                    .add(const Duration(days: 7))
                    .toUtc()
                    .toIso8601String()
              : null,
        },
      });
    }

    adapter.stub('/users/me', StubResponse.json(200, meEnvelope('pending')));
    adapter.stub(
      '/users/me/deletion',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'deletionStatus': null,
          'scheduledDeletionAt': null,
          'coolingOffDays': 7,
        }),
      ),
    );
    // 撤销后 invalidate 重新拉取：状态已清除。
    adapter.stub('/users/me', StubResponse.json(200, meEnvelope(null)));
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('删除已预约'), findsOneWidget);

    await tester.tap(find.text('撤销删除'));
    await tester.pumpAndSettle();
    expect(deletionService.cancelCalls, 1);
    expect(find.textContaining('已撤销删除申请'), findsOneWidget);

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

  testWidgets('关于区版本号读 package_info_plus（注入值上屏，非硬编码）', (tester) async {
    await pumpSettings(
      tester,
      extraOverrides: <Override>[
        appVersionLabelProvider.overrideWith((ref) async => '1.2.3 (4)'),
      ],
    );

    await scrollTo(tester, find.text('1.2.3 (4)'));
    expect(find.text('1.2.3 (4)'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsNothing); // 旧硬编码版本不再出现

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
    return '/tmp/eatwise_data_export_20260729.json';
  }
}

class _FakeDeletionService implements AccountDeletionService {
  int calls = 0;
  int cancelCalls = 0;

  @override
  Future<AccountDeletionView> requestDeletion() async {
    calls++;
    return AccountDeletionView(
      deletionStatus: 'pending',
      scheduledDeletionAt: DateTime.now().add(const Duration(days: 7)),
    );
  }

  @override
  Future<AccountDeletionView> cancelDeletion() async {
    cancelCalls++;
    return const AccountDeletionView();
  }
}

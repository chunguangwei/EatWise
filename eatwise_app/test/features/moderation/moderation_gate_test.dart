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
import 'package:eatwise/features/moderation/presentation/moderation_page.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

/// 审批中心入口门控（role 流转：GET /users/me 的 user.role → userMeProvider →
/// 设置页账号组）：admin 显示「审批中心」且可导航；普通用户/未登录完全不可见。
void main() {
  late SharedPreferences prefs;
  late FakeHttpAdapter adapter;
  late InMemoryTokenStore tokenStore;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    adapter = FakeHttpAdapter();
    tokenStore = InMemoryTokenStore();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  void stubUserMe(String? role) {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{
            'id': 'u-1',
            'username': 'tester',
            'role': ?role,
          },
        }),
      ),
    );
  }

  Future<void> pumpSettings(WidgetTester tester) async {
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
          path: '/moderation/food-candidates',
          builder: (context, state) => const ModerationPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            privacyConsentStoreProvider.overrideWithValue(
              InMemoryPrivacyConsentStore()..hasAgreedCurrentPolicy = true,
            ),
            privacyGateProvider.overrideWithValue(PrivacyGate(agreed: true)),
            consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
            analyticsClientsProvider.overrideWithValue(const []),
            tokenStoreProvider.overrideWithValue(tokenStore),
            authGateProvider.overrideWithValue(AuthGate()..loggedIn = true),
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
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin：账号组显示「审批中心」入口，点击进审批页', (tester) async {
    stubUserMe('admin');
    adapter.stub(
      '/moderation/food-candidates',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'items': const <Object?>[],
          'pageInfo': <String, Object?>{'nextCursor': null, 'hasMore': false},
        }),
      ),
    );
    await pumpSettings(tester);

    expect(find.text('审批中心'), findsOneWidget);
    await tester.tap(find.text('审批中心'));
    await tester.pumpAndSettle();
    expect(find.byType(ModerationPage), findsOneWidget);
    expect(find.text('暂无待审批的食品候选'), findsOneWidget);
  });

  testWidgets('普通用户（role=user）：不见「审批中心」入口', (tester) async {
    stubUserMe('user');
    await pumpSettings(tester);
    expect(find.text('审批中心'), findsNothing);
    expect(find.text('我的贡献'), findsOneWidget); // 相邻入口仍在
  });

  testWidgets('role 缺省（老服务端不下发）：按 user 门控，入口隐藏', (tester) async {
    stubUserMe(null);
    await pumpSettings(tester);
    expect(find.text('审批中心'), findsNothing);
  });
}

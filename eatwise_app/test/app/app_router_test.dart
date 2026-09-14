import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/app/router/app_router.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/login_page.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/presentation/legal_pages.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late PrivacyGate privacyGate;
  late OnboardingGate onboardingGate;
  late InMemoryTokenStore tokenStore;
  late GoRouter router;

  Future<void> pumpRouterApp(WidgetTester tester) async {
    router = createAppRouter(
      gate: onboardingGate,
      authGate: authGate,
      privacyGate: privacyGate,
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
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
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = FakeHttpAdapter();
    // 已同意隐私政策、未登录、引导未完成：聚焦登录门禁分支。
    authGate = AuthGate();
    privacyGate = PrivacyGate(agreed: true);
    onboardingGate = OnboardingGate(completed: false);
    tokenStore = InMemoryTokenStore();
  });

  group('登录门禁 redirect', () {
    testWidgets('未登录访问首页 → 重定向登录页', (tester) async {
      await pumpRouterApp(tester);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('未登录访问 /legal/privacy 与 /legal/agreement 不被弹回登录页', (
      tester,
    ) async {
      await pumpRouterApp(tester);
      expect(find.byType(LoginPage), findsOneWidget);

      router.go('/legal/privacy');
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('隐私政策'), findsWidgets);

      router.go('/legal/agreement');
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('用户协议'), findsWidgets);
    });

    testWidgets('未登录访问受保护路由（/record）仍弹回登录页', (tester) async {
      await pumpRouterApp(tester);
      router.go('/record');
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });
}

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/update/update_providers.dart';
import 'package:eatwise/core/update/update_throttle.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
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

/// 设置页「检查更新」（手动触发，不节流）：有更新弹窗、已是最新提示、
/// 失败提示、节流记录不影响手动检查。
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

  Map<String, dynamic> versionEnvelope({
    String latest = '1.2.0',
    String min = '1.0.0',
  }) {
    return StubResponse.envelope(<String, dynamic>{
      'latestVersion': latest,
      'minSupportedVersion': min,
      'releaseNotes': <String, String>{'zh': '- 新增更新检查', 'en': '- Update'},
      'apkUrl': 'https://example.com/app.apk',
      'publishedAt': null,
      'source': 'github',
    });
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    String currentVersion = '1.0.0',
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
            currentAppVersionProvider.overrideWithValue(
              () async => currentVersion,
            ),
            dataExportServiceProvider.overrideWithValue(_FakeExportService()),
            accountDeletionServiceProvider.overrideWithValue(
              _FakeDeletionService(),
            ),
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

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> tapCheckUpdate(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('检查更新'), 120);
    await tester.pump();
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('关于组含「检查更新」行；有更新弹更新弹窗', (tester) async {
    adapter.stub(
      '/app/version/latest',
      StubResponse.json(200, versionEnvelope()),
    );
    await pumpSettings(tester, currentVersion: '1.0.0');

    await tapCheckUpdate(tester);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('最新版本：1.2.0'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
    // 手动检查带 platform 查询参数。
    expect(adapter.requestsTo('/app/version/latest'), 1);
    expect(
      adapter.requests
          .firstWhere((r) => r.path == '/app/version/latest')
          .queryParameters['platform'],
      isNotNull,
    );

    await unmount(tester);
  });

  testWidgets('手动检查不节流：24h 内仍发起请求', (tester) async {
    // 预置「刚检查过」的节流记录。
    await prefs.setInt(
      UpdateCheckThrottle.lastCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    adapter.stub(
      '/app/version/latest',
      StubResponse.json(200, versionEnvelope()),
    );
    await pumpSettings(tester, currentVersion: '1.0.0');

    await tapCheckUpdate(tester);

    expect(adapter.requestsTo('/app/version/latest'), 1);
    expect(find.text('发现新版本'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('已是最新：SnackBar 提示，不弹更新弹窗', (tester) async {
    adapter.stub(
      '/app/version/latest',
      StubResponse.json(200, versionEnvelope()),
    );
    await pumpSettings(tester, currentVersion: '1.2.0');

    await tapCheckUpdate(tester);

    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.text('发现新版本'), findsNothing);

    await unmount(tester);
  });

  testWidgets('检查失败：SnackBar 提示稍后重试', (tester) async {
    adapter.stub('/app/version/latest', StubResponse.networkError('offline'));
    await pumpSettings(tester, currentVersion: '1.0.0');

    await tapCheckUpdate(tester);

    expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);

    await unmount(tester);
  });
}

class _FakeExportService implements DataExportService {
  @override
  Future<String> requestExport() => throw UnimplementedError();
}

class _FakeDeletionService implements AccountDeletionService {
  @override
  Future<AccountDeletionView> requestDeletion() => throw UnimplementedError();

  @override
  Future<AccountDeletionView> cancelDeletion() => throw UnimplementedError();
}

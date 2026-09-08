import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/change_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;

  Future<void> pumpChangePasswordPage(WidgetTester tester) async {
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
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ChangePasswordPage(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 预置登录态（改密页要求 Bearer）：注入令牌并打开门禁。
  Future<void> primeSession() async {
    await tokenStore.saveTokens(accessToken: 'at-1', refreshToken: 'rt-1');
    authGate.loggedIn = true;
  }

  Future<void> fillForm(
    WidgetTester tester, {
    required String oldPassword,
    required String newPassword,
    required String confirm,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), oldPassword);
    await tester.enterText(fields.at(1), newPassword);
    await tester.enterText(fields.at(2), confirm);
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = FakeHttpAdapter();
    authGate = AuthGate();
    tokenStore = InMemoryTokenStore();
  });

  group('修改密码页（zh-CN）', () {
    testWidgets('渲染表单：标题/旧密码/新密码/确认新密码，48px 输入框', (tester) async {
      await pumpChangePasswordPage(tester);
      expect(find.text('修改密码'), findsWidgets);
      expect(find.text('当前密码'), findsOneWidget);
      expect(find.text('新密码'), findsOneWidget);
      expect(find.text('确认新密码'), findsOneWidget);
      final fieldSize = tester.getSize(find.byType(TextField).first);
      expect(fieldSize.height, 48);
    });

    testWidgets('两次新密码不一致 → 客户端校验，不发请求', (tester) async {
      await pumpChangePasswordPage(tester);
      await fillForm(
        tester,
        oldPassword: 'passw0rd',
        newPassword: 'newpass1',
        confirm: 'newpass2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
      await tester.pump();
      expect(find.text('两次输入的新密码不一致'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('弱新密码（纯字母）→ 客户端强度校验，不发请求', (tester) async {
      await pumpChangePasswordPage(tester);
      await fillForm(
        tester,
        oldPassword: 'passw0rd',
        newPassword: 'onlyletters',
        confirm: 'onlyletters',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
      await tester.pump();
      expect(find.text('密码需 8-64 位且包含字母和数字'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('成功 → 请求携带 Bearer、Toast 提示、本地会话清除、门禁关闭', (tester) async {
      await primeSession();
      adapter.stub(
        '/auth/password/change',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{'changed': true}),
        ),
      );
      await pumpChangePasswordPage(tester);
      await fillForm(
        tester,
        oldPassword: 'passw0rd',
        newPassword: 'newpass1',
        confirm: 'newpass1',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('密码已修改，请重新登录'), findsOneWidget);
      expect(await tokenStore.accessToken, isNull);
      expect(await tokenStore.refreshToken, isNull);
      expect(authGate.loggedIn, isFalse);
      // Bearer 注入（拦截器读取本地 accessToken）。
      final request = adapter.requests.singleWhere(
        (r) => r.path == '/auth/password/change',
      );
      expect(request.headers['Authorization'], 'Bearer at-1');
    });

    testWidgets('旧密码错误 → AUTH_INVALID_CREDENTIALS 映射 i18n 文案，会话保持', (
      tester,
    ) async {
      await primeSession();
      adapter.stub(
        '/auth/password/change',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope(
            'AUTH_INVALID_CREDENTIALS',
            'server: old password wrong',
          ),
        ),
      );
      await pumpChangePasswordPage(tester);
      await fillForm(
        tester,
        oldPassword: 'badpass1',
        newPassword: 'newpass1',
        confirm: 'newpass1',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('用户名或密码错误'), findsOneWidget);
      expect(authGate.loggedIn, isTrue);
      expect(await tokenStore.refreshToken, isNotNull);
    });
  });

  group('修改密码页（en，D-15 双语）', () {
    testWidgets('英文文案渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpChangePasswordPage(tester);
      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('Confirm new password'), findsOneWidget);
    });
  });
}

/// 打开门禁模拟已登录（restore 会读 tokenStore）。

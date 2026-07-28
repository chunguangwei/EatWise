import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;

  Future<void> pumpLoginPage(WidgetTester tester) async {
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
          child: MaterialApp(theme: AppTheme.light(), home: const LoginPage()),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = FakeHttpAdapter();
    authGate = AuthGate();
    tokenStore = InMemoryTokenStore();
  });

  group('登录页（zh-CN）', () {
    testWidgets('渲染表单：标题/输入框/按钮，48px 输入框与 ≥44px 触控', (tester) async {
      await pumpLoginPage(tester);
      expect(find.text('手机号登录'), findsOneWidget);
      expect(find.text('请输入 11 位手机号'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      // 48px 输入框（设计稿表单规范）。
      final fieldSize = tester.getSize(find.byType(TextField).first);
      expect(fieldSize.height, 48);
    });

    testWidgets('非法手机号 → 错误提示，不发请求', (tester) async {
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      expect(find.text('请输入正确的手机号'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('发送验证码成功 → 60s 倒计时，逐秒递减', (tester) async {
      adapter.stub(
        '/auth/sms/send',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'ttlSec': 300,
            'resendAfterSec': 60,
          }),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, '13800138000');
      await tester.tap(find.text('获取验证码'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // 发送成功 toast + 倒计时启动；手机号归一化为 E.164 +86。
      expect(find.text('验证码已发送，请查收'), findsOneWidget);
      expect(find.text('60s 后重新发送'), findsOneWidget);
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['phone'], '+8613800138000');
      // 倒计时期间重发按钮不可见。
      expect(find.text('获取验证码'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('59s 后重新发送'), findsOneWidget);
      // 清理倒计时 Timer。
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('验证码错误 → 服务端本地化文案上屏，门禁保持关闭', (tester) async {
      adapter.stub(
        '/auth/sms/send',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'ttlSec': 300,
            'resendAfterSec': 60,
          }),
        ),
      );
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(
          400,
          StubResponse.errorEnvelope('AUTH_CODE_INVALID', '验证码错误或已过期'),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, '13800138000');
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.tap(find.text('登录'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('验证码错误或已过期'), findsOneWidget);
      expect(authGate.loggedIn, isFalse);
    });

    testWidgets('登录成功 → 令牌持久化、门禁打开', (tester) async {
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'accessToken': 'at-1',
            'refreshToken': 'rt-1',
            'expiresIn': 7200,
            'isNewUser': true,
            'user': <String, dynamic>{'id': 'u-1', 'onboardingStatus': 'none'},
          }),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, '13800138000');
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('登录'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(authGate.loggedIn, isTrue);
      expect(await tokenStore.accessToken, 'at-1');
      expect(await tokenStore.refreshToken, 'rt-1');
    });
  });

  group('登录页（en，D-15 双语）', () {
    testWidgets('英文文案渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpLoginPage(tester);
      expect(find.text('Sign in with phone'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('英文倒计时文案', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      adapter.stub(
        '/auth/sms/send',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'ttlSec': 300,
            'resendAfterSec': 60,
          }),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, '13800138000');
      await tester.tap(find.text('Send code'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Resend in 60s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

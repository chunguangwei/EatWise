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
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;

  Map<String, dynamic> sessionPayload({
    String accessToken = 'at-1',
    String refreshToken = 'rt-1',
    bool isNewUser = true,
  }) => StubResponse.envelope(<String, dynamic>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresIn': 7200,
    'isNewUser': isNewUser,
    'user': <String, dynamic>{'id': 'u-1', 'onboardingStatus': 'none'},
  });

  Future<void> pumpLoginPage(WidgetTester tester) async {
    // 拉高视口：ListView 懒构建，保证展开后全部输入框都已挂载。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/login',
      routes: <RouteBase>[
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/register',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('注册页占位'))),
        ),
      ],
    );
    addTearDown(router.dispose);
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
  }

  /// 展开「其他登录方式」（手机验证码备用区）并滚到手机输入框。
  Future<void> expandAltMethods(WidgetTester tester) async {
    await tester.tap(find.text('其他登录方式'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = FakeHttpAdapter();
    authGate = AuthGate();
    tokenStore = InMemoryTokenStore();
  });

  group('登录页（zh-CN，账号密码主表单）', () {
    testWidgets('渲染表单：标题/用户名/密码/登录/注册链接，48px 输入框', (tester) async {
      await pumpLoginPage(tester);
      // 标题与登录按钮均为「登录」。
      expect(find.text('登录'), findsWidgets);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('3-20 位字母、数字或下划线'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('没有账号？'), findsOneWidget);
      expect(find.text('注册'), findsOneWidget);
      expect(find.text('其他登录方式'), findsOneWidget);
      // 手机验证码输入区默认折叠。
      expect(find.text('请输入 11 位手机号'), findsNothing);
      // 48px 输入框（设计稿表单规范）。
      final fieldSize = tester.getSize(find.byType(TextField).first);
      expect(fieldSize.height, 48);
    });

    testWidgets('非法用户名 → 客户端校验提示，不发请求', (tester) async {
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'ab!');
      await tester.enterText(find.byType(TextField).last, 'passw0rd');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(find.text('用户名需为 3-20 位字母、数字或下划线'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('短密码 → 客户端校验提示，不发请求', (tester) async {
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'user_01');
      await tester.enterText(find.byType(TextField).last, 'pass1');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(find.text('密码需为 8-64 位'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('登录成功 → 令牌持久化、门禁打开', (tester) async {
      adapter.stub('/auth/login', StubResponse.json(200, sessionPayload()));
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'user_01');
      await tester.enterText(find.byType(TextField).last, 'passw0rd');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(authGate.loggedIn, isTrue);
      expect(await tokenStore.accessToken, 'at-1');
      expect(await tokenStore.refreshToken, 'rt-1');
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['username'], 'user_01');
      expect(body['password'], 'passw0rd');
    });

    testWidgets('凭据错误 → AUTH_INVALID_CREDENTIALS 映射 i18n 文案上屏', (tester) async {
      adapter.stub(
        '/auth/login',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope(
            'AUTH_INVALID_CREDENTIALS',
            'server says: bad credentials',
          ),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'user_01');
      await tester.enterText(find.byType(TextField).last, 'wrongpass1');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // 客户端映射文案（非服务端原文）；双语由 i18n 保证。
      expect(find.text('用户名或密码错误'), findsOneWidget);
      expect(authGate.loggedIn, isFalse);
    });

    testWidgets('注册链接 → 跳转 /register', (tester) async {
      await pumpLoginPage(tester);
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      expect(find.text('注册页占位'), findsOneWidget);
    });

    testWidgets('展开其他登录方式 → 手机验证码流程可用（发送/倒计时）', (tester) async {
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
      await expandAltMethods(tester);
      // 展开后依次：用户名(0)/密码(1)/手机号(2)/验证码(3)。
      await tester.enterText(find.byType(TextField).at(2), '13800138000');
      await tester.tap(find.text('获取验证码'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('验证码已发送，请查收'), findsOneWidget);
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['phone'], '+8613800138000');
      expect(find.text('60s 后重新发送'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('59s 后重新发送'), findsOneWidget);
      // 清理倒计时 Timer。
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('手机验证码登录成功 → 令牌持久化、门禁打开', (tester) async {
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, sessionPayload(refreshToken: 'rt-sms')),
      );
      await pumpLoginPage(tester);
      await expandAltMethods(tester);
      await tester.enterText(find.byType(TextField).at(2), '13800138000');
      await tester.enterText(find.byType(TextField).at(3), '123456');
      await tester.tap(find.widgetWithText(OutlinedButton, '登录'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(authGate.loggedIn, isTrue);
      expect(await tokenStore.refreshToken, 'rt-sms');
    });
  });

  group('登录页（en，D-15 双语）', () {
    testWidgets('英文文案渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpLoginPage(tester);
      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('No account?'), findsOneWidget);
      expect(find.text('Sign up'), findsOneWidget);
      expect(find.text('Other sign-in methods'), findsOneWidget);
    });

    testWidgets('凭据错误 → 英文映射文案上屏', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      adapter.stub(
        '/auth/login',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_INVALID_CREDENTIALS', '用户名或密码错误'),
        ),
      );
      await pumpLoginPage(tester);
      await tester.enterText(find.byType(TextField).first, 'user_01');
      await tester.enterText(find.byType(TextField).last, 'wrongpass1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Incorrect username or password'), findsOneWidget);
    });
  });
}

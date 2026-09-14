import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/auth/presentation/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;

  Map<String, dynamic> registerPayload({String refreshToken = 'rt-new'}) =>
      StubResponse.envelope(<String, dynamic>{
        'accessToken': 'at-new',
        'refreshToken': refreshToken,
        'expiresIn': 7200,
        'isNewUser': true,
        'user': <String, dynamic>{'id': 'u-9', 'onboardingStatus': 'none'},
      });

  Future<void> pumpRegisterPage(
    WidgetTester tester, {
    List<Override> extraOverrides = const <Override>[],
  }) async {
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
            ...extraOverrides,
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const RegisterPage(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    required String username,
    required String password,
    required String confirm,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), username);
    await tester.enterText(fields.at(1), password);
    await tester.enterText(fields.at(2), confirm);
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = FakeHttpAdapter();
    authGate = AuthGate();
    tokenStore = InMemoryTokenStore();
  });

  group('注册页（zh-CN）', () {
    testWidgets('渲染表单：标题/三个输入框/协议勾选/注册按钮，48px 输入框', (tester) async {
      await pumpRegisterPage(tester);
      expect(find.text('注册'), findsWidgets);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('确认密码'), findsOneWidget);
      expect(find.text('再次输入密码'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      final fieldSize = tester.getSize(find.byType(TextField).first);
      expect(fieldSize.height, 48);
    });

    testWidgets('非法用户名 → 客户端校验，不发请求', (tester) async {
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'ab',
        password: 'passw0rd',
        confirm: 'passw0rd',
      );
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump();
      expect(find.text('用户名需为 3-20 位字母、数字或下划线'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('两次密码不一致 → 校验提示，不发请求', (tester) async {
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'new_user',
        password: 'passw0rd',
        confirm: 'passw0rd2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump();
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('未勾选协议 → 校验提示，不发请求', (tester) async {
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'new_user',
        password: 'passw0rd',
        confirm: 'passw0rd',
      );
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump();
      expect(find.text('请先阅读并同意隐私政策与用户协议'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('密码强度实时提示：弱/中/强', (tester) async {
      await pumpRegisterPage(tester);
      final fields = find.byType(TextField);
      // 弱：仅长度够
      await tester.enterText(fields.at(1), 'passw0rd');
      await tester.pump();
      expect(find.text('密码强度：弱'), findsOneWidget);
      // 中：字母+数字+特殊字符
      await tester.enterText(fields.at(1), 'Passw0rd!');
      await tester.pump();
      expect(find.text('密码强度：中'), findsOneWidget);
      // 强：≥12 且三类
      await tester.enterText(fields.at(1), 'Passw0rd!123');
      await tester.pump();
      expect(find.text('密码强度：强'), findsOneWidget);
    });

    testWidgets('密码强度条：输入 1/5/7 位（不足 8 位）提示至少 8 位且不崩溃', (tester) async {
      await pumpRegisterPage(tester);
      final fields = find.byType(TextField);
      for (final short in <String>['a', 'abcde', 'abcdefg']) {
        await tester.enterText(fields.at(1), short);
        await tester.pump();
        // strength=0 且非空：只给长度提示，不得取 labels[-1] 崩溃。
        expect(find.text('密码长度至少 8 位'), findsOneWidget);
        expect(find.text('密码强度：弱'), findsNothing);
      }
      // 达到 8 位后恢复强度评级。
      await tester.enterText(fields.at(1), 'passw0rd');
      await tester.pump();
      expect(find.text('密码强度：弱'), findsOneWidget);
      expect(find.text('密码长度至少 8 位'), findsNothing);
    });

    testWidgets('注册成功 → 自动登录：令牌持久化、门禁打开', (tester) async {
      adapter.stub('/auth/register', StubResponse.json(201, registerPayload()));
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'new_user',
        password: 'passw0rd',
        confirm: 'passw0rd',
      );
      // 勾选协议
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(authGate.loggedIn, isTrue);
      expect(await tokenStore.accessToken, 'at-new');
      expect(await tokenStore.refreshToken, 'rt-new');
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['username'], 'new_user');
      expect(body['password'], 'passw0rd');
    });

    testWidgets('用户名占用 → AUTH_USERNAME_TAKEN 映射 i18n 文案', (tester) async {
      adapter.stub(
        '/auth/register',
        StubResponse.json(
          409,
          StubResponse.errorEnvelope('AUTH_USERNAME_TAKEN', 'taken'),
        ),
      );
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'taken_user',
        password: 'passw0rd',
        confirm: 'passw0rd',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('用户名已被使用'), findsOneWidget);
      expect(authGate.loggedIn, isFalse);
    });

    testWidgets('弱密码（纯数字）→ 客户端强度校验，不发请求', (tester) async {
      await pumpRegisterPage(tester);
      await fillForm(
        tester,
        username: 'new_user',
        password: '12345678',
        confirm: '12345678',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pump();
      expect(find.text('密码需 8-64 位且包含字母和数字'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    });

    testWidgets('进入注册页清掉上一页残留的登录失败文案（共享 AuthState）', (tester) async {
      // 预置一次登录失败残留：共享 AuthState 带上 AUTH_INVALID_CREDENTIALS
      // （runAsync 跳出 FakeAsync 走真实事件循环完成 fake adapter 请求）。
      final dio = createApiDio(config: ApiConfig(), tokenStore: tokenStore);
      dio.httpClientAdapter = adapter;
      final controller = AuthController(
        api: AuthApi(dio),
        tokenStore: tokenStore,
        gate: authGate,
      );
      adapter.stub(
        '/auth/login',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_INVALID_CREDENTIALS', 'bad'),
        ),
      );
      await tester.runAsync(() async {
        await expectLater(
          controller.loginWithPassword(
            username: 'old_user',
            password: 'passw0rd',
          ),
          throwsA(isA<ApiException>()),
        );
      });
      expect(controller.state.errorCode, 'AUTH_INVALID_CREDENTIALS');

      await pumpRegisterPage(
        tester,
        extraOverrides: <Override>[
          authControllerProvider.overrideWith((ref) => controller),
        ],
      );
      // 页面进入后残留错误已清除，注册页不再展示登录失败文案。
      expect(find.text('用户名或密码错误'), findsNothing);
      expect(controller.state.errorCode, isNull);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('注册页（en，D-15 双语）', () {
    testWidgets('英文文案渲染', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await pumpRegisterPage(tester);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Create an account to get started'), findsOneWidget);
    });
  });
}

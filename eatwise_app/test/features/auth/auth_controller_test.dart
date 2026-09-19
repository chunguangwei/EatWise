import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late InMemoryTokenStore tokenStore;
  late AuthGate gate;
  late AuthController controller;

  Map<String, dynamic> loginPayload({
    String accessToken = 'at-1',
    String refreshToken = 'rt-1',
    bool isNewUser = true,
  }) => StubResponse.envelope(<String, dynamic>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresIn': 7200,
    'isNewUser': isNewUser,
    'user': <String, dynamic>{
      'id': 'u-1',
      'nickname': null,
      'locale': 'zh-CN',
      'timezone': 'Asia/Shanghai',
      'goal': null,
      'onboardingStatus': 'none',
    },
  });

  setUp(() {
    adapter = FakeHttpAdapter();
    tokenStore = InMemoryTokenStore();
    gate = AuthGate();
    final dio = createApiDio(config: ApiConfig(), tokenStore: tokenStore);
    dio.httpClientAdapter = adapter;
    dio.interceptors
            .whereType<AuthInterceptor>()
            .single
            .refreshDio
            .httpClientAdapter =
        adapter;
    controller = AuthController(
      api: AuthApi(dio),
      tokenStore: tokenStore,
      gate: gate,
    );
  });

  group('restore', () {
    test('无 refreshToken → loggedOut，门禁关闭', () async {
      await controller.restore();
      expect(controller.state.status, AuthStatus.loggedOut);
      expect(gate.loggedIn, isFalse);
    });

    test('有 refreshToken → loggedIn，门禁打开', () async {
      await tokenStore.saveTokens(accessToken: 'a', refreshToken: 'r');
      await controller.restore();
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(gate.loggedIn, isTrue);
    });

    test('有 refreshToken + 持久化 userId → userId 一并恢复（B1 冷启动回归）', () async {
      await tokenStore.saveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'u-9',
      );
      await controller.restore();
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(controller.state.userId, 'u-9');
    });

    test('旧版本会话（无持久化 userId）→ loggedIn 且 userId 保持 null', () async {
      await tokenStore.saveTokens(accessToken: 'a', refreshToken: 'r');
      await controller.restore();
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(controller.state.userId, isNull);
    });
  });

  group('sendCode', () {
    test('成功返回重发秒数（E.164 手机号）', () async {
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
      final resendAfterSec = await controller.sendCode('+8613800138000');
      expect(resendAfterSec, 60);
      expect(controller.state.sendingCode, isFalse);
      expect(controller.state.errorCode, isNull);
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['phone'], '+8613800138000');
      expect(body['scene'], 'login');
    });

    test('429 限流 → errorCode=RATE_LIMITED 并上屏文案', () async {
      adapter.stub(
        '/auth/sms/send',
        StubResponse.json(
          429,
          StubResponse.errorEnvelope('RATE_LIMITED', '发送太频繁，请 30 秒后再试'),
        ),
      );
      await expectLater(
        controller.sendCode('+8613800138000'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'RATE_LIMITED');
      expect(controller.state.errorMessage, '发送太频繁，请 30 秒后再试');
    });
  });

  group('loginWithPhone（手机验证码备用）', () {
    test('成功：令牌持久化、门禁打开、状态 loggedIn', () async {
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, loginPayload(refreshToken: 'rt-9')),
      );
      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(controller.state.userId, 'u-1');
      expect(controller.state.isNewUser, isTrue);
      expect(gate.loggedIn, isTrue);
      // userId 随令牌持久化（冷启动 restore 恢复依赖，v1.2.1 走查 B1）。
      expect(await tokenStore.userId, 'u-1');
      expect(await tokenStore.accessToken, 'at-1');
      expect(await tokenStore.refreshToken, 'rt-9');
    });

    test('验证码错误 → errorCode=AUTH_CODE_INVALID，门禁保持关闭', () async {
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(
          400,
          StubResponse.errorEnvelope(
            'AUTH_CODE_INVALID',
            '验证码错误或已过期',
            details: <String, dynamic>{'remainingAttempts': 3},
          ),
        ),
      );
      await expectLater(
        controller.loginWithPhone(phone: '+8613800138000', code: '000000'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_CODE_INVALID');
      expect(controller.state.errorMessage, '验证码错误或已过期');
      expect(controller.state.status, isNot(AuthStatus.loggedIn));
      expect(gate.loggedIn, isFalse);
      expect(await tokenStore.refreshToken, isNull);
    });
  });

  group('登录恢复 onboarding 状态（v1.12.4 走查：重装老账号被重导根因）', () {
    Map<String, dynamic> payloadWithOnboarding(String status) =>
        StubResponse.envelope(<String, dynamic>{
          'accessToken': 'at-1',
          'refreshToken': 'rt-1',
          'expiresIn': 7200,
          'isNewUser': false,
          'user': <String, dynamic>{
            'id': 'u-1',
            'nickname': null,
            'locale': 'zh-CN',
            'timezone': 'Asia/Shanghai',
            'goal': null,
            'onboardingStatus': status,
          },
        });

    test('服务端 completed → 内存门禁 + 持久化存储双写（杀进程重开不再进引导）', () async {
      final onboardingStore = InMemoryOnboardingStore();
      final onboardingGate = OnboardingGate(completed: false);
      controller = AuthController(
        api: AuthApi(
          createApiDio(config: ApiConfig(), tokenStore: tokenStore)
            ..httpClientAdapter = adapter,
        ),
        tokenStore: tokenStore,
        gate: gate,
        onboardingGate: onboardingGate,
        onboardingStore: onboardingStore,
      );
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, payloadWithOnboarding('completed')),
      );

      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');

      // 内存门禁即时翻转（登录后路由直接进首页，不闪引导页）。
      expect(onboardingGate.completed, isTrue);
      // 持久化完成标记：模拟杀进程重开——main() 冷启动仅从存储重建门禁。
      expect(onboardingStore.isOnboardingCompleted, isTrue);
      final coldStartGate = OnboardingGate(
        completed: onboardingStore.isOnboardingCompleted,
      );
      expect(coldStartGate.completed, isTrue);
    });

    test('服务端 skipped → 同样恢复完成态（跳过=不再引导）', () async {
      final onboardingStore = InMemoryOnboardingStore();
      final onboardingGate = OnboardingGate(completed: false);
      controller = AuthController(
        api: AuthApi(
          createApiDio(config: ApiConfig(), tokenStore: tokenStore)
            ..httpClientAdapter = adapter,
        ),
        tokenStore: tokenStore,
        gate: gate,
        onboardingGate: onboardingGate,
        onboardingStore: onboardingStore,
      );
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, payloadWithOnboarding('skipped')),
      );

      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');

      expect(onboardingGate.completed, isTrue);
      expect(onboardingStore.isOnboardingCompleted, isTrue);
    });

    test('服务端 none（新注册/未引导）→ 不写完成态，行为不变正常走引导', () async {
      final onboardingStore = InMemoryOnboardingStore();
      final onboardingGate = OnboardingGate(completed: false);
      controller = AuthController(
        api: AuthApi(
          createApiDio(config: ApiConfig(), tokenStore: tokenStore)
            ..httpClientAdapter = adapter,
        ),
        tokenStore: tokenStore,
        gate: gate,
        onboardingGate: onboardingGate,
        onboardingStore: onboardingStore,
      );
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, payloadWithOnboarding('none')),
      );

      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');

      expect(onboardingGate.completed, isFalse);
      expect(onboardingStore.isOnboardingCompleted, isFalse);
    });

    test('引导存储未装配（纯认证环境）→ 仅内存门禁，不崩', () async {
      final onboardingGate = OnboardingGate(completed: false);
      controller = AuthController(
        api: AuthApi(
          createApiDio(config: ApiConfig(), tokenStore: tokenStore)
            ..httpClientAdapter = adapter,
        ),
        tokenStore: tokenStore,
        gate: gate,
        onboardingGate: onboardingGate,
      );
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, payloadWithOnboarding('completed')),
      );

      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');

      expect(onboardingGate.completed, isTrue);
    });
  });

  group('loginWithPassword（R2 账号密码登录）', () {
    test('成功：令牌持久化、门禁打开、状态 loggedIn', () async {
      adapter.stub(
        '/auth/login',
        StubResponse.json(200, loginPayload(refreshToken: 'rt-pw')),
      );
      await controller.loginWithPassword(
        username: 'user_01',
        password: 'passw0rd',
      );
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(gate.loggedIn, isTrue);
      expect(await tokenStore.refreshToken, 'rt-pw');
      expect(controller.state.loggingIn, isFalse);
      final body = adapter.requestBodies.single as Map<dynamic, dynamic>;
      expect(body['username'], 'user_01');
      expect(body['password'], 'passw0rd');
    });

    test('凭据错误 → errorCode=AUTH_INVALID_CREDENTIALS，门禁保持关闭', () async {
      adapter.stub(
        '/auth/login',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_INVALID_CREDENTIALS', '用户名或密码错误'),
        ),
      );
      await expectLater(
        controller.loginWithPassword(username: 'user_01', password: 'wrong123'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_INVALID_CREDENTIALS');
      expect(controller.state.loggingIn, isFalse);
      expect(gate.loggedIn, isFalse);
      expect(await tokenStore.refreshToken, isNull);
    });
  });

  group('register（R1 注册即登录）', () {
    test('成功：令牌持久化、门禁打开、isNewUser', () async {
      adapter.stub(
        '/auth/register',
        StubResponse.json(201, loginPayload(refreshToken: 'rt-new')),
      );
      await controller.register(username: 'new_user', password: 'passw0rd');
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(controller.state.isNewUser, isTrue);
      expect(controller.state.registering, isFalse);
      expect(gate.loggedIn, isTrue);
      expect(await tokenStore.refreshToken, 'rt-new');
    });

    test('用户名占用 → errorCode=AUTH_USERNAME_TAKEN，门禁保持关闭', () async {
      adapter.stub(
        '/auth/register',
        StubResponse.json(
          409,
          StubResponse.errorEnvelope('AUTH_USERNAME_TAKEN', '用户名已被使用'),
        ),
      );
      await expectLater(
        controller.register(username: 'taken', password: 'passw0rd'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_USERNAME_TAKEN');
      expect(controller.state.registering, isFalse);
      expect(gate.loggedIn, isFalse);
    });

    test('弱密码 → errorCode=AUTH_PASSWORD_TOO_WEAK', () async {
      adapter.stub(
        '/auth/register',
        StubResponse.json(
          400,
          StubResponse.errorEnvelope('AUTH_PASSWORD_TOO_WEAK', '密码强度不足'),
        ),
      );
      await expectLater(
        controller.register(username: 'new_user', password: '12345678'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_PASSWORD_TOO_WEAK');
    });
  });

  group('changePassword（R3 改密后全端下线）', () {
    test('成功：清本地令牌、门禁关闭、状态 loggedOut', () async {
      adapter.stub('/auth/login', StubResponse.json(200, loginPayload()));
      await controller.loginWithPassword(
        username: 'user_01',
        password: 'passw0rd',
      );
      adapter.stub(
        '/auth/password/change',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{'changed': true}),
        ),
      );
      await controller.changePassword(
        oldPassword: 'passw0rd',
        newPassword: 'newpass1',
      );
      expect(controller.state.status, AuthStatus.loggedOut);
      expect(controller.state.changingPassword, isFalse);
      expect(gate.loggedIn, isFalse);
      expect(await tokenStore.accessToken, isNull);
      expect(await tokenStore.refreshToken, isNull);
    });

    test('旧密码错误 → 会话保持，errorCode=AUTH_INVALID_CREDENTIALS', () async {
      adapter.stub('/auth/login', StubResponse.json(200, loginPayload()));
      await controller.loginWithPassword(
        username: 'user_01',
        password: 'passw0rd',
      );
      adapter.stub(
        '/auth/password/change',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_INVALID_CREDENTIALS', '原密码不正确'),
        ),
      );
      await expectLater(
        controller.changePassword(
          oldPassword: 'badpass1',
          newPassword: 'newpass1',
        ),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_INVALID_CREDENTIALS');
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(gate.loggedIn, isTrue);
      expect(await tokenStore.refreshToken, isNotNull);
      expect(controller.state.changingPassword, isFalse);
    });
  });

  group('logout / onSessionCleared', () {
    test('登出：尽力通知服务端，清令牌、门禁关闭', () async {
      adapter.stub('/auth/login/phone', StubResponse.json(200, loginPayload()));
      await controller.loginWithPhone(phone: '+8613800138000', code: '123456');
      adapter.stub(
        '/auth/logout',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{'loggedOut': true}),
        ),
      );
      await controller.logout();
      expect(controller.state.status, AuthStatus.loggedOut);
      expect(gate.loggedIn, isFalse);
      expect(await tokenStore.accessToken, isNull);
    });

    test('登出时服务端不可达也允许本地登出', () async {
      await tokenStore.saveTokens(accessToken: 'a', refreshToken: 'r');
      await controller.restore();
      adapter.stub('/auth/logout', StubResponse.networkError('offline'));
      await controller.logout();
      expect(controller.state.status, AuthStatus.loggedOut);
      expect(await tokenStore.refreshToken, isNull);
    });

    test('onSessionCleared（refresh 失败被拦截器清会话）→ 强制登出', () async {
      await tokenStore.saveTokens(accessToken: 'a', refreshToken: 'r');
      await controller.restore();
      expect(gate.loggedIn, isTrue);
      controller.onSessionCleared();
      expect(controller.state.status, AuthStatus.loggedOut);
      expect(gate.loggedIn, isFalse);
    });
  });

  group('clearError（共享 AuthState，页面进入时清残留错误）', () {
    test('登录失败后 clearError 清空 errorCode/errorMessage', () async {
      adapter.stub(
        '/auth/login',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_INVALID_CREDENTIALS', '用户名或密码错误'),
        ),
      );
      await expectLater(
        controller.loginWithPassword(username: 'user_1', password: 'passw0rd'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_INVALID_CREDENTIALS');
      expect(controller.state.errorMessage, isNotNull);

      controller.clearError();

      expect(controller.state.errorCode, isNull);
      expect(controller.state.errorMessage, isNull);
    });

    test('无错误时 clearError 为空操作（不触发状态变化）', () {
      final before = controller.state;
      controller.clearError();
      expect(identical(controller.state, before), isTrue);
    });
  });
}

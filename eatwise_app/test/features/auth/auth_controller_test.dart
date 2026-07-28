import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
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

  group('login', () {
    test('成功：令牌持久化、门禁打开、状态 loggedIn', () async {
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(200, loginPayload(refreshToken: 'rt-9')),
      );
      await controller.login(phone: '+8613800138000', code: '123456');
      expect(controller.state.status, AuthStatus.loggedIn);
      expect(controller.state.userId, 'u-1');
      expect(controller.state.isNewUser, isTrue);
      expect(gate.loggedIn, isTrue);
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
        controller.login(phone: '+8613800138000', code: '000000'),
        throwsA(isA<BusinessApiException>()),
      );
      expect(controller.state.errorCode, 'AUTH_CODE_INVALID');
      expect(controller.state.errorMessage, '验证码错误或已过期');
      expect(controller.state.status, isNot(AuthStatus.loggedIn));
      expect(gate.loggedIn, isFalse);
      expect(await tokenStore.refreshToken, isNull);
    });
  });

  group('logout / onSessionCleared', () {
    test('登出：尽力通知服务端，清令牌、门禁关闭', () async {
      adapter.stub('/auth/login/phone', StubResponse.json(200, loginPayload()));
      await controller.login(phone: '+8613800138000', code: '123456');
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
}

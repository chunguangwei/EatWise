import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late InMemoryTokenStore tokenStore;
  late int sessionClearedCount;
  late Dio dio;

  setUp(() {
    adapter = FakeHttpAdapter();
    tokenStore = InMemoryTokenStore();
    sessionClearedCount = 0;
    dio = createApiDio(
      config: ApiConfig(),
      tokenStore: tokenStore,
      localeTag: () => 'zh-CN',
      timezoneName: () => 'Asia/Shanghai',
      onSessionCleared: () => sessionClearedCount++,
    );
    dio.httpClientAdapter = adapter;
    // 拦截器内部的 refresh 裸 Dio 与主 Dio 共享同一 fake adapter。
    final auth = dio.interceptors.whereType<AuthInterceptor>().single;
    auth.refreshDio.httpClientAdapter = adapter;
  });

  group('ApiHeadersInterceptor / EnvelopeInterceptor', () {
    test('请求携带 Accept-Language 与 X-Timezone，成功信封解包为 data', () async {
      adapter.stub(
        '/foods/search',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{'items': <dynamic>[]}),
        ),
      );
      final response = await dio.get<Map<String, dynamic>>('/foods/search');
      expect(response.data, <String, dynamic>{'items': <dynamic>[]});
      expect(response.extra['serverTime'], '2026-07-27T12:00:00.000Z');
      final sent = adapter.requests.single;
      expect(sent.headers['Accept-Language'], 'zh-CN');
      expect(sent.headers['X-Timezone'], 'Asia/Shanghai');
    });

    test('错误信封解包为 BusinessApiException（code/message/details）', () async {
      adapter.stub(
        '/auth/sms/send',
        StubResponse.json(
          429,
          StubResponse.errorEnvelope(
            'RATE_LIMITED',
            '发送太频繁，请 42 秒后再试',
            details: <String, dynamic>{'retryAfterSec': 42},
          ),
        ),
      );
      try {
        await dio.post<void>('/auth/sms/send');
        fail('应抛出 BusinessApiException');
      } on DioException catch (e) {
        final error = toApiException(e);
        expect(error, isA<BusinessApiException>());
        final business = error as BusinessApiException;
        expect(business.code, 'RATE_LIMITED');
        expect(business.message, '发送太频繁，请 42 秒后再试');
        expect(business.retryAfterSec, 42);
        expect(business.isRetryable, isTrue);
      }
    });

    test('网络错误映射为 NetworkApiException', () async {
      adapter.stub('/x', StubResponse.networkError('socket closed'));
      try {
        await dio.get<void>('/x');
        fail('应抛出');
      } on DioException catch (e) {
        expect(toApiException(e), isA<NetworkApiException>());
      }
    });
  });

  group('AuthInterceptor', () {
    test('已登录请求注入 Authorization: Bearer', () async {
      await tokenStore.saveTokens(accessToken: 'at-1', refreshToken: 'rt-1');
      adapter.stub(
        '/fasting/status',
        StubResponse.json(200, StubResponse.envelope(<String, dynamic>{})),
      );
      await dio.get<void>('/fasting/status');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer at-1');
    });

    test('401 → refresh 换令牌并重放原请求一次（新 token）', () async {
      await tokenStore.saveTokens(accessToken: 'at-old', refreshToken: 'rt-1');
      adapter.stub(
        '/sync/pull',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', '令牌已过期'),
        ),
      );
      adapter.stub(
        '/auth/refresh',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'accessToken': 'at-new',
            'refreshToken': 'rt-2',
            'expiresIn': 7200,
          }),
        ),
      );
      adapter.stub(
        '/sync/pull',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'changes': <dynamic>[],
            'syncToken': 'st_1',
            'hasMore': false,
          }),
        ),
      );

      final response = await dio.get<Map<String, dynamic>>('/sync/pull');

      expect((response.data!['syncToken']), 'st_1');
      // 顺序：原请求 401 → refresh → 重放原请求。
      expect(adapter.requests.map((r) => r.path).toList(), <String>[
        '/sync/pull',
        '/auth/refresh',
        '/sync/pull',
      ]);
      expect(adapter.requests.last.headers['Authorization'], 'Bearer at-new');
      // refresh 滑动轮换：新 refreshToken 已持久化。
      expect(await tokenStore.refreshToken, 'rt-2');
      expect(sessionClearedCount, 0);
    });

    test('multipart 上传 401 → refresh 后重放：FormData 克隆重建不抛 StateError', () async {
      await tokenStore.saveTokens(accessToken: 'at-old', refreshToken: 'rt-1');
      adapter.stub(
        '/posts',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', '令牌已过期'),
        ),
      );
      adapter.stub(
        '/auth/refresh',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'accessToken': 'at-new',
            'refreshToken': 'rt-2',
            'expiresIn': 7200,
          }),
        ),
      );
      adapter.stub(
        '/posts',
        StubResponse.json(
          201,
          StubResponse.envelope(<String, dynamic>{'id': 'p-1'}),
        ),
      );

      final formData = FormData.fromMap(<String, dynamic>{
        'caption': '早餐打卡',
        'image': MultipartFile.fromBytes(<int>[1, 2, 3, 4], filename: 'a.jpg'),
      });
      final response = await dio.post<Map<String, dynamic>>(
        '/posts',
        data: formData,
      );

      expect(response.data!['id'], 'p-1');
      // 顺序：原请求 401（消费了原 FormData）→ refresh → 克隆体重放成功。
      expect(adapter.requests.map((r) => r.path).toList(), <String>[
        '/posts',
        '/auth/refresh',
        '/posts',
      ]);
      expect(adapter.requests.last.headers['Authorization'], 'Bearer at-new');
      // 重放体为克隆 FormData：字段与文件完整保留。
      final replayedBody = adapter.requests.last.data! as FormData;
      expect(replayedBody, isNot(same(formData)));
      expect(
        replayedBody.fields.map((e) => '${e.key}=${e.value}'),
        contains('caption=早餐打卡'),
      );
      expect(replayedBody.files.single.key, 'image');
    });

    test('skipAuth 请求（登录/发短信）不注入 token、401 不触发 refresh', () async {
      await tokenStore.saveTokens(accessToken: 'at-1', refreshToken: 'rt-1');
      adapter.stub(
        '/auth/login/phone',
        StubResponse.json(
          400,
          StubResponse.errorEnvelope('AUTH_CODE_INVALID', '验证码错误或已过期'),
        ),
      );
      try {
        await dio.post<void>(
          '/auth/login/phone',
          options: Options(extra: const <String, dynamic>{'skipAuth': true}),
        );
        fail('应抛出');
      } on DioException catch (e) {
        expect(
          (toApiException(e) as BusinessApiException).code,
          'AUTH_CODE_INVALID',
        );
      }
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(adapter.requestsTo('/auth/refresh'), 0);
    });

    test('refresh 失败 → 清会话并回调 onSessionCleared', () async {
      await tokenStore.saveTokens(accessToken: 'at-old', refreshToken: 'rt-x');
      adapter.stub(
        '/sync/pull',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', '令牌已过期'),
        ),
      );
      adapter.stub(
        '/auth/refresh',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_REFRESH_REUSED', '登录状态已失效'),
        ),
      );

      try {
        await dio.get<void>('/sync/pull');
        fail('应抛出');
      } on DioException catch (e) {
        expect(
          (toApiException(e) as BusinessApiException).code,
          'AUTH_TOKEN_EXPIRED',
        );
      }
      expect(await tokenStore.accessToken, isNull);
      expect(await tokenStore.refreshToken, isNull);
      expect(sessionClearedCount, 1);
      // 不重放原请求。
      expect(adapter.requestsTo('/sync/pull'), 1);
    });

    test('refresh 轮换后后续请求自动携带新 accessToken（不重复 refresh）', () async {
      await tokenStore.saveTokens(accessToken: 'at-old', refreshToken: 'rt-1');
      adapter.stub(
        '/a',
        StubResponse.json(
          401,
          StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', 'x'),
        ),
      );
      adapter.stub(
        '/auth/refresh',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'accessToken': 'at-new',
            'refreshToken': 'rt-2',
            'expiresIn': 7200,
          }),
        ),
      );
      adapter.stub('/a', StubResponse.json(200, StubResponse.envelope(true)));
      adapter.stub('/b', StubResponse.json(200, StubResponse.envelope(true)));

      await dio.get<dynamic>('/a');
      await dio.get<dynamic>('/b');

      // QueuedInterceptor 串行化 + 单飞：全程仅 refresh 一次，
      // 后续请求在 onRequest 注入轮换后的新 token（旧 refreshToken 不重放）。
      expect(adapter.requestsTo('/auth/refresh'), 1);
      final bRequest = adapter.requests.firstWhere((r) => r.path == '/b');
      expect(bRequest.headers['Authorization'], 'Bearer at-new');
      expect(await tokenStore.refreshToken, 'rt-2');
    });
  });
}

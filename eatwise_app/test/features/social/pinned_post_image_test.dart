import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/social/presentation/pinned_post_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/network/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late InMemoryTokenStore tokenStore;
  late Dio dio;
  late ProviderContainer container;

  setUp(() async {
    adapter = FakeHttpAdapter();
    tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(accessToken: 'at-old', refreshToken: 'rt-1');
    dio = createApiDio(
      config: ApiConfig(),
      tokenStore: tokenStore,
      localeTag: () => 'zh-CN',
      timezoneName: () => 'Asia/Shanghai',
    );
    dio.httpClientAdapter = adapter;
    dio.interceptors
            .whereType<AuthInterceptor>()
            .single
            .refreshDio
            .httpClientAdapter =
        adapter;
    container = ProviderContainer(
      overrides: <Override>[apiDioProvider.overrideWithValue(dio)],
    );
  });

  tearDown(() {
    container.dispose();
    dio.close();
  });

  test('帖图加载器对同源与跨源图片都显式 skipAuth', () async {
    final apiOrigin = Uri.parse(dio.options.baseUrl).origin;
    final sameOriginUrl = '$apiOrigin/v1/uploads/same.png';
    const crossOriginUrl = 'https://images.eatwise.invalid/a.png';
    adapter.stub(sameOriginUrl, StubResponse.rawBytes(200, <int>[1, 2, 3]));
    adapter.stub(crossOriginUrl, StubResponse.rawBytes(200, <int>[4, 5, 6]));
    final loader = container.read(pinnedPostImageLoaderProvider);

    expect(await loader.load(sameOriginUrl), <int>[1, 2, 3]);
    expect(await loader.load(crossOriginUrl), <int>[4, 5, 6]);

    expect(adapter.requests, hasLength(2));
    for (final request in adapter.requests) {
      expect(request.extra['skipAuth'], isTrue);
      expect(request.headers.containsKey('Authorization'), isFalse);
    }
    expect(adapter.requestsTo('/auth/refresh'), 0);
  });

  test('跨源帖图 401 不 refresh、不重放且会话保留', () async {
    const crossOriginUrl = 'https://images.eatwise.invalid/unauthorized.png';
    adapter.stub(
      crossOriginUrl,
      StubResponse.json(
        401,
        StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', '令牌已过期'),
      ),
    );
    final loader = container.read(pinnedPostImageLoaderProvider);

    expect(await loader.load(crossOriginUrl), isNull);

    expect(adapter.requests.single.path, crossOriginUrl);
    expect(adapter.requests.single.extra['skipAuth'], isTrue);
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
    expect(adapter.requestsTo('/auth/refresh'), 0);
    expect(await tokenStore.accessToken, 'at-old');
    expect(await tokenStore.refreshToken, 'rt-1');
  });
}

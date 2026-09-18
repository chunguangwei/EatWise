import 'dart:io';

import 'package:dio/io.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/cert_pinning.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldPinCert', () {
    test('仅 https + wcg.polin.tech 启用锁定（端口任意）', () {
      expect(shouldPinCert('https://wcg.polin.tech:8443/v1'), isTrue);
      expect(shouldPinCert('https://wcg.polin.tech/v1'), isTrue);
    });

    test('http 开发地址 / 其它域名 / 非法地址不锁定', () {
      expect(shouldPinCert('http://172.23.28.168:3000/v1'), isFalse);
      expect(shouldPinCert('http://wcg.polin.tech:8443/v1'), isFalse);
      expect(shouldPinCert('https://api.eatwise.example.com/v1'), isFalse);
      expect(shouldPinCert('not-a-url'), isFalse);
      expect(shouldPinCert(''), isFalse);
    });
  });

  group('loadPinnedSecurityContext', () {
    test('从 PEM 字节构造只信任该证书的 SecurityContext', () async {
      final pem = await File('assets/certs/wcg.polin.tech.pem').readAsBytes();
      final context = await loadPinnedSecurityContext(
        assetReader: (_) async => pem.buffer.asByteData(),
      );
      expect(context, isA<SecurityContext>());
    });
  });

  group('createApiDio 证书锁定接入', () {
    test(
      '传入 pinnedSecurityContext 后主 Dio 与 refresh 裸 Dio 均换绑锁定 HttpClient',
      () async {
        final pem = await File('assets/certs/wcg.polin.tech.pem').readAsBytes();
        final context = SecurityContext(withTrustedRoots: false);
        context.setTrustedCertificatesBytes(pem);
        final dio = createApiDio(
          config: ApiConfig(),
          tokenStore: InMemoryTokenStore(),
          pinnedSecurityContext: context,
        );
        // dio 默认适配器 createHttpClient 为 null；锁定后必须显式换绑。
        final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
        expect(adapter.createHttpClient, isNotNull);
        final auth = dio.interceptors.whereType<AuthInterceptor>().single;
        final refreshAdapter =
            auth.refreshDio.httpClientAdapter as IOHttpClientAdapter;
        expect(refreshAdapter.createHttpClient, isNotNull);
        adapter.createHttpClient!().close();
        refreshAdapter.createHttpClient!().close();
      },
    );

    test('不传 pinnedSecurityContext 保持默认适配器（createHttpClient 为 null）', () {
      final dio = createApiDio(config: ApiConfig());
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNull);
    });
  });
}

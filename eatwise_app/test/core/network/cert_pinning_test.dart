import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  group('pemToDer', () {
    test('真实资产 PEM 解码出 DER，与去头尾行拼接的 base64 解码一致', () async {
      final pem = await File('assets/certs/wcg.polin.tech.pem').readAsString();
      final der = pemToDer(pem);
      // DER 编码的 X.509 证书以 SEQUENCE（0x30）开头。
      expect(der.first, 0x30);
      expect(der.length, greaterThan(500));
      final expected = base64Decode(
        pem
            .split('\n')
            .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
            .map((l) => l.trim())
            .join(),
      );
      expect(der, expected);
    });

    test('容忍 CRLF 与首尾空白', () {
      const body = 'AQIDBA=='; // [1, 2, 3, 4]
      final der = pemToDer(
        '\r\n-----BEGIN CERTIFICATE-----\r\n$body\r\n-----END CERTIFICATE-----\r\n',
      );
      expect(der, Uint8List.fromList(<int>[1, 2, 3, 4]));
    });
  });

  group('derEquals / allowPinnedCert', () {
    final der = Uint8List.fromList(<int>[0x30, 0x03, 0x02, 0x01, 0x05]);

    test('DER 逐字节比对：相等/不等/长度不同', () {
      expect(derEquals(Uint8List.fromList(der), der), isTrue);
      final tampered = Uint8List.fromList(der)..[4] = 0x06;
      expect(derEquals(tampered, der), isFalse);
      expect(derEquals(Uint8List.fromList(<int>[0x30]), der), isFalse);
    });

    test('仅锁定 host 且 DER 一致才放行', () {
      expect(allowPinnedCert(der, 'wcg.polin.tech', der), isTrue);
      expect(allowPinnedCert(der, 'evil.example.com', der), isFalse);
      expect(
        allowPinnedCert(Uint8List.fromList(<int>[0x30]), 'wcg.polin.tech', der),
        isFalse,
      );
    });
  });

  group('loadPinnedCertDer', () {
    test('从资产 PEM 字节解码出 DER', () async {
      final pem = await File('assets/certs/wcg.polin.tech.pem').readAsBytes();
      final der = await loadPinnedCertDer(
        assetReader: (_) async => pem.buffer.asByteData(),
      );
      expect(der.first, 0x30);
      expect(der, pemToDer(utf8.decode(pem)));
    });
  });

  group('in-process TLS 握手（端到端验证 badCertificateCallback 路径）', () {
    // 私钥不入库的环境（CI）跳过：纯函数用例已覆盖判定逻辑。
    final keyFile = File('../eatwise_server/deploy/certs/key.pem');

    test('DER 一致握手通过 / 篡改 DER 握手被拒', () async {
      if (!keyFile.existsSync()) {
        // ignore: avoid_print
        print('跳过握手用例：$keyFile 不存在');
        return;
      }
      final pemBytes = await File(
        'assets/certs/wcg.polin.tech.pem',
      ).readAsBytes();
      final pinnedDer = pemToDer(utf8.decode(pemBytes));
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(pemBytes)
        ..usePrivateKeyBytes(await keyFile.readAsBytes());
      final server = await SecureServerSocket.bind(
        '127.0.0.1',
        0,
        serverContext,
      );
      final subs = <StreamSubscription<dynamic>>[];
      server.listen((socket) {
        subs.add(socket.listen((_) {}, onError: (_) {}));
      });
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
        await server.close();
      });

      Future<bool> handshakeWith(Uint8List pin) async {
        final raw = await Socket.connect('127.0.0.1', server.port);
        try {
          // 与生产路径同款：host 传锁定域名，系统验证自签名必失败，
          // 走到 onBadCertificate 做 DER 比对。
          final secure = await SecureSocket.secure(
            raw,
            host: pinnedCertHost,
            onBadCertificate: (cert) => allowPinnedCert(
              Uint8List.fromList(cert.der),
              pinnedCertHost,
              pin,
            ),
          );
          await secure.close();
          return true;
        } on Object {
          raw.destroy();
          return false;
        }
      }

      expect(await handshakeWith(pinnedDer), isTrue);
      final tampered = Uint8List.fromList(pinnedDer)..[10] ^= 0xFF;
      expect(await handshakeWith(tampered), isFalse);
    });
  });

  group('createApiDio 证书锁定接入', () {
    final pinnedDer = Uint8List.fromList(<int>[0x30, 0x03, 0x02, 0x01, 0x05]);

    test('传入 pinnedCertDer 后主 Dio 与 refresh 裸 Dio 均换绑锁定 HttpClient', () {
      final dio = createApiDio(
        config: ApiConfig(),
        tokenStore: InMemoryTokenStore(),
        pinnedCertDer: pinnedDer,
      );
      // dio 默认适配器 createHttpClient 为 null；锁定后必须显式换绑。
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNotNull);
      adapter.createHttpClient!().close();
      final auth = dio.interceptors.whereType<AuthInterceptor>().single;
      final refreshAdapter =
          auth.refreshDio.httpClientAdapter as IOHttpClientAdapter;
      expect(refreshAdapter.createHttpClient, isNotNull);
      refreshAdapter.createHttpClient!().close();
    });

    test('不传 pinnedCertDer 保持默认适配器（createHttpClient 为 null）', () {
      final dio = createApiDio(config: ApiConfig());
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNull);
    });
  });
}

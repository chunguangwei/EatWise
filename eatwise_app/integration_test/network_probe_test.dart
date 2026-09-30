import 'package:dio/dio.dart';
import 'package:eatwise/core/network/cert_pinning.dart';
import 'package:eatwise/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 网络探针（一次性）：真机诊断登录链路。
/// 1) 局域网 dev server 可达性；2) 生产 https + 证书锁定握手；3) 生产登录。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('network probe', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 5));

    // 1) 局域网 dev server（Mac 本机）
    final localDio = Dio(
      BaseOptions(
        baseUrl: 'http://172.23.20.126:3000/v1',
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final res = await localDio.get<Object?>('/health');
      debugPrint('@@PROBE: local health ${res.statusCode}@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: local health error $e@@');
    }

    // 2/3) 生产 + 证书锁定（与 apiDioProvider 相同的握手路径）
    final prodDio = Dio(
      BaseOptions(
        baseUrl: 'https://wcg.polin.tech:8443/v1',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final der = await loadPinnedCertDer();
      applyCertPinning(prodDio, der);
      debugPrint('@@PROBE: pinning applied ${der.length} bytes@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: pinning load error $e@@');
    }
    try {
      final res = await prodDio.get<Object?>('/health');
      debugPrint('@@PROBE: prod health ${res.statusCode}@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: prod health error $e@@');
    }
    try {
      final res = await prodDio.post<Object?>(
        '/auth/login',
        data: <String, dynamic>{
          'username': 'appreview',
          'password': 'Review#2026EatWise',
        },
      );
      debugPrint('@@PROBE: prod login ${res.statusCode}@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: prod login error $e@@');
    }
  });
}

import 'package:dio/dio.dart';
import 'package:eatwise/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 网络探针（一次性）：真机直连生产服务器诊断（登录卡死的根因排查）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('network probe', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 5));
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://wcg.polin.tech:8443/v1',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final res = await dio.get<Object?>('/health');
      debugPrint('@@PROBE: health ${res.statusCode}@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: health error $e@@');
    }
    try {
      final res = await dio.post<Object?>(
        '/auth/login',
        data: <String, dynamic>{
          'username': 'appreview',
          'password': 'Review#2026EatWise',
        },
      );
      debugPrint('@@PROBE: login ${res.statusCode}@@');
    } on Object catch (e) {
      debugPrint('@@PROBE: login error $e@@');
    }
  });
}

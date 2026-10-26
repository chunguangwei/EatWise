import 'package:dio/dio.dart';
import 'package:eatwise/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'qa_environment.dart';

/// Local-only network probe for an isolated QA app and memory server.
/// Requires EATWISE_QA=true and an explicit private/loopback API_BASE_URL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local QA network probe', (tester) async {
    final api = requireLocalQaApi();
    await app.main();
    await tester.pump(const Duration(seconds: 5));
    final dio = Dio(
      BaseOptions(
        baseUrl: api,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    addTearDown(dio.close);
    final health = await dio.get<Object?>('/health');
    expect(health.statusCode, 200);
    final login = await dio.post<Object?>(
      '/auth/login',
      data: <String, dynamic>{
        'username': 'appreview',
        'password': 'Review#2026EatWise',
      },
    );
    expect(login.statusCode, 200);
  });
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) => handler(options);
  @override
  void close({bool force = false}) {}
}

Dio _dioWith(Future<ResponseBody> Function(RequestOptions) handler) =>
    Dio()..httpClientAdapter = _FakeAdapter(handler);

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const cfg = LlmConfig(
  provider: 'custom',
  baseUrl: 'http://192.168.1.10:11434/v1',
  model: 'qwen3:4b',
);

Future<InMemoryLlmConfigStore> storeWith(LlmConfig c) async {
  final s = InMemoryLlmConfigStore();
  await s.save(c);
  return s;
}

void main() {
  test('成功：解析 chat/completions 响应', () async {
    final client = UserLlmClient(
      store: await storeWith(cfg),
      dio: _dioWith((o) async {
        expect(o.path, 'http://192.168.1.10:11434/v1/chat/completions');
        return _json({
          'choices': [
            {
              'message': {
                'content':
                    '{"kcal":120,"protein_g":8,"carb_g":15,"fat_g":3,"confidence":"high"}',
              },
            },
          ],
        });
      }),
    );
    final est = await client.estimate('番茄炒蛋');
    expect(est.per100g.kcal, 120);
    expect(est.confidence, 'high');
  });

  test('容忍 ```json 包裹；非法 confidence 按 low', () async {
    final client = UserLlmClient(
      store: await storeWith(cfg),
      dio: _dioWith(
        (o) async => _json({
          'choices': [
            {
              'message': {
                'content':
                    '```json\n{"kcal":100,"protein_g":5,"carb_g":10,"fat_g":2,"confidence":"???"}\n```',
              },
            },
          ],
        }),
      ),
    );
    final est = await client.estimate('x');
    expect(est.isLowConfidence, isTrue);
  });

  test(
    '字段缺失/越界/非 200/连接失败/未配置 → ESTIMATE_UNAVAILABLE（isEstimateUnavailable 为真）',
    () async {
      for (final handler in <Future<ResponseBody> Function(RequestOptions)>[
        (o) async => _json({
          'choices': [
            {
              'message': {'content': '{"kcal":100}'},
            },
          ],
        }),
        (o) async => _json({
          'choices': [
            {
              'message': {
                'content': '{"kcal":9999,"protein_g":5,"carb_g":10,"fat_g":2}',
              },
            },
          ],
        }),
        (o) async => _json({}, status: 500),
        (o) async => throw DioException(
          type: DioExceptionType.connectionError,
          requestOptions: o,
          error: 'refused',
        ),
      ]) {
        final client = UserLlmClient(
          store: await storeWith(cfg),
          dio: _dioWith(handler),
        );
        await expectLater(
          client.estimate('x'),
          throwsA(
            predicate((e) => e is ApiException && isEstimateUnavailable(e)),
          ),
        );
      }
      // 未配置：store 为空直接抛，不发请求
      final noCfg = UserLlmClient(
        store: InMemoryLlmConfigStore(),
        dio: _dioWith((o) async => throw StateError('不应发请求')),
      );
      await expectLater(
        noCfg.estimate('x'),
        throwsA(
          predicate((e) => e is ApiException && isEstimateUnavailable(e)),
        ),
      );
    },
  );
}

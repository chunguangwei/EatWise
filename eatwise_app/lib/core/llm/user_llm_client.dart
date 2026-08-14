import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 营养值合法区间（与服务端 food.rules isPer100gInRange 同口径）。
bool _inRange(NutritionSnapshot p) =>
    p.kcal >= 0 &&
    p.kcal <= 900 &&
    p.proteinG >= 0 &&
    p.proteinG <= 100 &&
    p.carbG >= 0 &&
    p.carbG <= 100 &&
    p.fatG >= 0 &&
    p.fatG <= 100;

/// 与服务端 SYSTEM_PROMPT 逐字一致（openai-compatible.provider.ts）。
const String _systemPrompt =
    '你是中餐营养估算助手。根据用户给出的菜名（可能附带描述），估算每 100g 可食部的营养值。\n'
    '只返回 JSON，不要输出任何其他文字或 Markdown 代码块：\n'
    '{"kcal": number, "protein_g": number, "carb_g": number, "fat_g": number, "confidence": "high"|"medium"|"low"}\n'
    '约束：kcal 0-900，其余 0-100；confidence 表示你对该估算的把握程度。';

/// 用户端估算出口（编排器依赖此窄接口，测试注入 Fake）。
abstract interface class UserEstimateSource {
  Future<FoodEstimate> estimate(String name, {String? description});
}

/// 用户自定义 LLM 直连客户端（规格 §3）：POST {baseUrl}/chat/completions。
/// 不复用 apiDioProvider（其拦截器面向服务端信封/鉴权）；独立裸 Dio。
/// 一切失败抛 503 ESTIMATE_UNAVAILABLE，由编排器决定回落（规格 §6）。
final class UserLlmClient implements UserEstimateSource {
  UserLlmClient({Dio? dio, required this.store}) : _dio = dio ?? Dio();

  final Dio _dio;
  final LlmConfigStore store;
  static const Duration _timeout = Duration(seconds: 15);

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    final cfg = (await store.read())?.effective();
    if (cfg == null || !cfg.isComplete) throw _unavailable();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${cfg.baseUrl}/chat/completions',
        options: Options(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: {
            'content-type': 'application/json',
            if (cfg.apiKey != null && cfg.apiKey!.isNotEmpty)
              'authorization': 'Bearer ${cfg.apiKey}',
          },
        ),
        data: {
          'model': cfg.model,
          'temperature': 0.2,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {
              'role': 'user',
              'content': (description != null && description.isNotEmpty)
                  ? '菜名：$name\n描述：$description'
                  : '菜名：$name',
            },
          ],
        },
      );
      final choices = response.data?['choices'];
      final first = choices is List && choices.isNotEmpty
          ? choices.first
          : null;
      final message = first is Map<String, dynamic> ? first['message'] : null;
      final content = message is Map<String, dynamic>
          ? message['content']
          : null;
      if (content is! String) throw _unavailable();
      return _parse(content);
    } on ApiException {
      rethrow;
    } on Object {
      throw _unavailable();
    }
  }

  /// 容忍 ```json 代码块包裹；字段缺失/非数值/越界一律拒绝。
  FoodEstimate _parse(String content) {
    var text = content.trim();
    text = text.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      throw _unavailable();
    }
    double? numOf(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    final kcal = numOf('kcal'),
        protein = numOf('protein_g'),
        carb = numOf('carb_g'),
        fat = numOf('fat_g');
    if (kcal == null || protein == null || carb == null || fat == null) {
      throw _unavailable();
    }
    final snapshot = NutritionSnapshot(
      kcal: kcal,
      proteinG: protein,
      carbG: carb,
      fatG: fat,
    );
    if (!_inRange(snapshot)) throw _unavailable();
    const allowed = {'high', 'medium', 'low'};
    final c = raw['confidence'];
    return FoodEstimate(
      per100g: snapshot,
      confidence: c is String && allowed.contains(c) ? c : 'low',
    );
  }

  BusinessApiException _unavailable() => const BusinessApiException(
    httpStatus: 503,
    code: 'ESTIMATE_UNAVAILABLE',
    message: 'estimate unavailable',
  );
}

import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = FoodEstimate(
  per100g: NutritionSnapshot(kcal: 100, proteinG: 5, carbG: 10, fatG: 2),
  confidence: 'high',
);

/// 用户端估算窄抽象替身：ok=false 时模拟直连失败（503 ESTIMATE_UNAVAILABLE）。
final class _FakeUserClient implements UserEstimateSource {
  _FakeUserClient({required this.ok});

  final bool ok;

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    if (!ok) {
      throw const BusinessApiException(
        httpStatus: 503,
        code: 'ESTIMATE_UNAVAILABLE',
        message: 'estimate unavailable',
      );
    }
    return _sample;
  }
}

void main() {
  test('未配置 → 直走服务端，usedFallback=false', () async {
    final remote = FakeCustomFoodRemote()..estimateResult = _sample;
    final orch = FoodEstimateOrchestrator(
      store: InMemoryLlmConfigStore(),
      userClient: _FakeUserClient(ok: true),
      remote: remote,
    );
    final out = await orch.estimate('x');
    expect(out.usedFallback, isFalse);
    expect(remote.estimateCount, 1);
  });

  test('已配置且直连成功 → 不走服务端', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final remote = FakeCustomFoodRemote();
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: true),
      remote: remote,
    );
    final out = await orch.estimate('x');
    expect(out.usedFallback, isFalse);
    expect(out.estimate.per100g.kcal, _sample.per100g.kcal);
    expect(remote.estimateCount, 0);
  });

  test('直连失败 → 回落服务端，usedFallback=true', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final remote = FakeCustomFoodRemote()..estimateResult = _sample;
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: false),
      remote: remote,
    );
    final out = await orch.estimate('x');
    expect(out.usedFallback, isTrue);
    expect(out.estimate.per100g.kcal, _sample.per100g.kcal);
  });

  test('双失败 → 抛 ESTIMATE_UNAVAILABLE', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: false),
      remote: FakeCustomFoodRemote(
        mode: FakeCustomFoodMode.estimateUnavailable,
      ),
    );
    await expectLater(orch.estimate('x'), throwsA(isA<ApiException>()));
  });
}

import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_nutrition_estimator.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
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
  int calls = 0;

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    calls++;
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

/// 端侧估算源 Fake：可脚本化 就绪/永久禁用/成功/解析失败/抛错，记录调用。
final class _FakeOnDeviceSource implements OnDeviceEstimateSource {
  bool ready = true;
  bool permanentlyDisabled = false;
  Object? error;
  OnDeviceNutritionEstimate? result = const OnDeviceNutritionEstimate(
    values: OnDeviceNutritionValues(
      kcal: 150,
      proteinG: 8,
      carbsG: 12,
      fatG: 6,
    ),
    dubious: false,
  );
  int calls = 0;

  @override
  bool get isPermanentlyDisabled => permanentlyDisabled;

  @override
  bool get isReady => ready;

  @override
  Future<OnDeviceNutritionEstimate?> estimate(String foodName) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

/// 判定为「估算不可用」（UI 降级手动填写分支的同一口径）。
Matcher get _unavailable => throwsA(
  isA<BusinessApiException>()
      .having((e) => e.httpStatus, 'httpStatus', 503)
      .having((e) => e.code, 'code', 'ESTIMATE_UNAVAILABLE'),
);

void main() {
  test('未配置用户 API → 抛 503 ESTIMATE_UNAVAILABLE（无服务端兜底）', () async {
    final orch = FoodEstimateOrchestrator(
      store: InMemoryLlmConfigStore(),
      userClient: _FakeUserClient(ok: true),
    );
    await expectLater(orch.estimate('x'), _unavailable);
  });

  test('已配置且直连成功 → source=userApi', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: true),
    );
    final out = await orch.estimate('x');
    expect(out.source, FoodEstimateSource.userApi);
    expect(out.estimate.per100g.kcal, _sample.per100g.kcal);
  });

  test('直连失败 → 抛 503 ESTIMATE_UNAVAILABLE（不再回落服务端）', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: false),
    );
    await expectLater(orch.estimate('x'), _unavailable);
  });

  group('端侧优先级（开关开且模型就绪 → 端侧 → 用户 API）', () {
    late _FakeOnDeviceSource onDevice;

    setUp(() {
      onDevice = _FakeOnDeviceSource();
    });

    FoodEstimateOrchestrator build({
      bool enabled = true,
      _FakeUserClient? userClient,
      LlmConfigStore? store,
    }) {
      return FoodEstimateOrchestrator(
        store: store ?? InMemoryLlmConfigStore(),
        userClient: userClient ?? _FakeUserClient(ok: true),
        onDeviceEnabled: () => enabled,
        onDeviceSource: () => onDevice,
      );
    }

    test('端侧成功 → source=ondevice 预填，不再触碰用户 API', () async {
      final userClient = _FakeUserClient(ok: true);
      final out = await build(userClient: userClient).estimate('番茄炒蛋');

      expect(out.source, FoodEstimateSource.ondevice);
      expect(out.estimate.per100g.kcal, 150);
      expect(out.estimate.per100g.proteinG, 8);
      expect(out.estimate.per100g.carbG, 12);
      expect(out.estimate.per100g.fatG, 6);
      expect(out.estimate.confidence, 'medium');
      expect(onDevice.calls, 1);
      expect(userClient.calls, 0);
    });

    test('端侧 dubious（sanity-clamp 命中）→ confidence=low 仍预填', () async {
      onDevice.result = const OnDeviceNutritionEstimate(
        values: OnDeviceNutritionValues(
          kcal: 320,
          proteinG: 5,
          carbsG: 79,
          fatG: 2,
        ),
        dubious: true,
      );
      final out = await build().estimate('香蕉');

      expect(out.source, FoodEstimateSource.ondevice);
      expect(out.estimate.isLowConfidence, isTrue);
      expect(out.estimate.per100g.kcal, 320);
    });

    test('开关关闭 → 跳过端侧（零调用）；未配置 API → 估算不可用', () async {
      await expectLater(build(enabled: false).estimate('x'), _unavailable);
      expect(onDevice.calls, 0);
    });

    test('模型未就绪 → 跳过端侧不触发下载（端侧零调用）', () async {
      onDevice.ready = false;
      await expectLater(build().estimate('x'), _unavailable);
      expect(onDevice.calls, 0);
    });

    test('端侧引擎错误 → 静默降级下一级（已配置用户 API）', () async {
      onDevice.error = const OnDeviceLlmEngineException('推理失败');
      final store = InMemoryLlmConfigStore();
      await store.save(
        const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
      );
      final userClient = _FakeUserClient(ok: true);
      final out = await build(
        store: store,
        userClient: userClient,
      ).estimate('x');

      expect(out.source, FoodEstimateSource.userApi);
      expect(userClient.calls, 1);
    });

    test('端侧解析失败（返回 null）→ 静默降级；无可用级 → 估算不可用', () async {
      onDevice.result = null;
      await expectLater(build().estimate('x'), _unavailable);
      expect(onDevice.calls, 1);
    });

    test('端侧 OOM → 静默降级；永久禁用后后续估算不再触碰端侧', () async {
      onDevice.error = const OnDeviceLlmMemoryException('引擎加载内存不足');

      await expectLater(build().estimate('x'), _unavailable);
      expect(onDevice.calls, 1);

      // 估算器内部置永久禁用（Fake 模拟）：编排器不再调用端侧。
      onDevice
        ..permanentlyDisabled = true
        ..error = null;
      await expectLater(build().estimate('y'), _unavailable);
      expect(onDevice.calls, 1, reason: '永久禁用后不再尝试端侧');
    });
  });
}

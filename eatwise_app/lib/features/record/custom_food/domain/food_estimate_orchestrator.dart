import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';

/// 估算结果 + 是否发生了「直连失败回落服务端」。
final class EstimateOutcome {
  const EstimateOutcome({required this.estimate, required this.usedFallback});

  /// 估算结果（直连或服务端回落产物）。
  final FoodEstimate estimate;

  /// true = 用户模型直连失败，已回落服务端估算（UI 提示一次）。
  final bool usedFallback;
}

/// 两级回落编排（规格 §2）：已配置 → 直连用户模型；未配置/直连失败 → 服务端。
class FoodEstimateOrchestrator {
  FoodEstimateOrchestrator({
    required this._store,
    required this._userClient,
    required this._remote,
  });

  final LlmConfigStore _store;
  final UserEstimateSource _userClient;
  final CustomFoodRemote _remote;

  /// 估算入口：未配置/配置不完整直走服务端（不算回落）；已配置先直连，
  /// 直连任何失败回落服务端并标记 usedFallback；双失败异常原样上抛。
  Future<EstimateOutcome> estimate(String name, {String? description}) async {
    final config = (await _store.read())?.effective();
    if (config == null || !config.isComplete) {
      return EstimateOutcome(
        estimate: await _remote.estimate(name, description: description),
        usedFallback: false,
      );
    }
    try {
      return EstimateOutcome(
        estimate: await _userClient.estimate(name, description: description),
        usedFallback: false,
      );
    } on Object {
      return EstimateOutcome(
        estimate: await _remote.estimate(name, description: description),
        usedFallback: true,
      );
    }
  }
}

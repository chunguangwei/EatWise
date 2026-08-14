import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自定义食物远程端（生产 REST；测试 override 为 FakeCustomFoodRemote）。
final Provider<CustomFoodRemote> customFoodRemoteProvider =
    Provider<CustomFoodRemote>((ref) {
      return RemoteCustomFoodApi(dio: ref.watch(apiDioProvider));
    });

/// 自定义食物仓储（远端直调 + 本地 drift 落库，离线 pending 重试）。
final Provider<CustomFoodRepository> customFoodRepositoryProvider =
    Provider<CustomFoodRepository>((ref) {
      return CustomFoodRepository(
        db: ref.watch(recordRepositoryProvider).db,
        remote: ref.watch(customFoodRemoteProvider),
      );
    });

/// 用户自定义 LLM 配置存储（main.dart 用 SharedPreferences 实例 override
/// 为 LocalLlmConfigStore；测试 override 为 InMemoryLlmConfigStore）。
final Provider<LlmConfigStore> llmConfigStoreProvider =
    Provider<LlmConfigStore>(
      (ref) => throw UnimplementedError('override in main'),
    );

/// 估算编排器（两级回落：已配置直连用户模型，未配置/直连失败回落服务端）。
final Provider<FoodEstimateOrchestrator> foodEstimateOrchestratorProvider =
    Provider<FoodEstimateOrchestrator>((ref) {
      final store = ref.watch(llmConfigStoreProvider);
      return FoodEstimateOrchestrator(
        store: store,
        userClient: UserLlmClient(store: store),
        remote: ref.watch(customFoodRemoteProvider),
      );
    });

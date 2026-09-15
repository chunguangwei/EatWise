import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
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

/// 用户模型直连客户端（测试 override 为 Fake 窄接口替身）。
final Provider<UserEstimateSource> userEstimateSourceProvider =
    Provider<UserEstimateSource>((ref) {
      return UserLlmClient(store: ref.watch(llmConfigStoreProvider));
    });

/// 端侧估算源（生产 = 核心层估算器适配；测试 override 为 Fake，
/// 避免 widget 测试触碰磁盘/推理插件）。
final Provider<OnDeviceEstimateSource> onDeviceEstimateSourceProvider =
    Provider<OnDeviceEstimateSource>((ref) {
      return OnDeviceEstimatorSource(
        ref.watch(onDeviceNutritionEstimatorProvider),
      );
    });

/// 估算编排器（两级：端侧（开关开且模型就绪）→ 已配置直连用户模型；
/// 两级都不可用抛 503，UI 降级手动填写。端侧源惰性获取，开关关闭时
/// 不实例化推理网关）。
final Provider<FoodEstimateOrchestrator> foodEstimateOrchestratorProvider =
    Provider<FoodEstimateOrchestrator>((ref) {
      return FoodEstimateOrchestrator(
        store: ref.watch(llmConfigStoreProvider),
        userClient: ref.watch(userEstimateSourceProvider),
        onDeviceEnabled: () => ref.read(onDeviceAiEnabledProvider),
        onDeviceSource: () => ref.read(onDeviceEstimateSourceProvider),
      );
    });

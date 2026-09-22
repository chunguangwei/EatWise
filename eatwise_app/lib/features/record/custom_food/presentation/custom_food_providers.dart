import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/custom_food/application/contribution_review.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
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

/// 驳回通知 tick（有新通知入队即 +1；记录页 listen 后 drain 展示）。
final StateProvider<int> contributionNoticeTickProvider = StateProvider<int>(
  (ref) => 0,
);

/// 贡献审核状态存储（按当前用户命名空间；prefs 未装配时降级内存）。
final Provider<ContributionStatusStore> contributionStatusStoreProvider =
    Provider<ContributionStatusStore>((ref) {
      try {
        return ContributionStatusStore(
          ref.watch(sharedPreferencesProvider),
          userId: ref.watch(currentUserIdProvider),
        );
      } on Object {
        return ContributionStatusStore.inMemory();
      }
    });

/// 贡献审核状态同步（记录同步/进入记录页时拉取「我的贡献」diff 状态迁移：
/// approved 转正去标记；rejected 清记录 + 一次性提示）。
final Provider<ContributionReviewSync> contributionReviewSyncProvider =
    Provider<ContributionReviewSync>((ref) {
      return ContributionReviewSync(
        db: ref.watch(recordRepositoryProvider).db,
        remote: ref.watch(customFoodRemoteProvider),
        store: ref.watch(contributionStatusStoreProvider),
        userId: ref.watch(currentUserIdProvider),
        onNoticesAdded: () =>
            ref.read(contributionNoticeTickProvider.notifier).state++,
        // 徽标即时消失：本地行 contributionStatus 被改写后失效记录行食物
        // 缓存（entryFoodProvider 非 autoDispose 一次性读，不失效则本会话
        // 内「审核中」徽标常驻——真机走查缺陷）。
        onStatusApplied: (_) => ref.invalidate(entryFoodProvider),
      );
    });

import 'dart:async';

import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/food_search_remote.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// 记录同步远程端（M7 真实 REST 实现；测试 override 为 FakeRecordRemote）。
final Provider<RecordRemote> recordRemoteProvider = Provider<RecordRemote>((
  ref,
) {
  return RemoteRecordSync(dio: ref.watch(apiDioProvider), location: tz.local);
});

/// M3 记录仓库。
///
/// 〔集成说明〕时区用 `tz.local`，需启动时初始化 timezone 数据库
/// （见 M2 计时模块既有做法）。
final Provider<RecordRepository> recordRepositoryProvider =
    Provider<RecordRepository>((ref) {
      final repo = RecordRepository(
        db: ref.watch(appDatabaseProvider),
        remote: ref.watch(recordRemoteProvider),
        location: tz.local,
      );
      ref.onDispose(() => unawaited(repo.dispose()));
      return repo;
    });

/// 搜索关键词（食物搜索输入框）。
final StateProvider<String> recordSearchQueryProvider = StateProvider<String>(
  (ref) => '',
);

/// 食物搜索（D-16）：本地优先 + 远端 K1 补充（远端结果合入本地缓存）；
/// dio 不可用/远端失败时静默降级为纯本地 drift 双语搜索。
final Provider<RemoteFoodSearch> remoteFoodSearchProvider =
    Provider<RemoteFoodSearch>((ref) {
      return RemoteFoodSearch(
        dio: ref.watch(apiDioProvider),
        db: ref.watch(recordRepositoryProvider).db,
      );
    });

/// 双语食物搜索结果（D-15/D-16）。
final FutureProvider<List<Food>> recordFoodSearchProvider =
    FutureProvider<List<Food>>((ref) async {
      final query = ref.watch(recordSearchQueryProvider);
      try {
        return await ref.watch(remoteFoodSearchProvider).search(query);
      } on Object {
        // 防御：网络层未装配（如测试只注入仓储）时降级纯本地。
        return ref.read(recordRepositoryProvider).searchFoods(query);
      }
    });

/// 记录同步引擎（启动/登录成功后 syncNow：先上行 pending 再增量下行）。
final Provider<RecordSyncEngine> recordSyncEngineProvider =
    Provider<RecordSyncEngine>((ref) {
      return RecordSyncEngine(
        repository: ref.watch(recordRepositoryProvider),
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });

/// 当前选中的食物（确认前可修改份量）。
final StateProvider<Food?> recordSelectedFoodProvider = StateProvider<Food?>(
  (ref) => null,
);

/// 份量输入（克，字符串原样持有以便编辑中校验）。
final StateProvider<String> recordAmountTextProvider = StateProvider<String>(
  (ref) => '100',
);

/// 份量修改实时重算的营养预览（US-3.1）。
final Provider<NutritionSnapshot?> recordDraftNutritionProvider =
    Provider<NutritionSnapshot?>((ref) {
      final food = ref.watch(recordSelectedFoodProvider);
      if (food == null) return null;
      final amount = double.tryParse(ref.watch(recordAmountTextProvider));
      if (amount == null || amount <= 0) return null;
      return NutritionSnapshot.forAmount(food, amount);
    });

/// 「待同步 N 条」计数流（§4.1 记录页顶部信息条）。
final StreamProvider<int> recordPendingCountProvider = StreamProvider<int>((
  ref,
) {
  return ref.watch(recordRepositoryProvider).watchPendingCount();
});

/// 今日聚合缓存流（本地预估，§2.6；角标注明「待云端校准」）。
final StreamProvider<DailyNutritionCache?> recordTodayNutritionProvider =
    StreamProvider<DailyNutritionCache?>((ref) {
      return ref
          .watch(recordRepositoryProvider)
          .watchDailyNutrition(DateTime.now());
    });

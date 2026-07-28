import 'dart:async';

import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// 记录同步远程端（M3 用 Fake 模拟；M7 替换为真实 REST 实现）。
final Provider<RecordRemote> recordRemoteProvider = Provider<RecordRemote>((
  ref,
) {
  return FakeRecordRemote();
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

/// 双语食物搜索结果（D-15/D-16）。
final FutureProvider<List<Food>> recordFoodSearchProvider =
    FutureProvider<List<Food>>((ref) {
      return ref
          .watch(recordRepositoryProvider)
          .searchFoods(ref.watch(recordSearchQueryProvider));
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

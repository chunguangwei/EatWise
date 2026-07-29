import 'dart:async';

import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/food_search_remote.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/frequent_foods.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';
import 'package:eatwise/features/record/recognition/voice/voice_text_parser.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
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

// ---- M3 三入口（拍照识别 / 语音录入 / 常吃复用，PRD M3 / D-16） ----

/// 本次入账的录入方式（三入口各自写入；手动搜索为默认）。
final StateProvider<EntrySource> recordEntrySourceProvider =
    StateProvider<EntrySource>((ref) => EntrySource.manual);

/// 结果卡是否标「请确认」（拍照低置信度，PRD M3 异常与边界）。
final StateProvider<bool> recordLowConfidenceProvider = StateProvider<bool>(
  (ref) => false,
);

/// 拍照/相册取图（生产 ImagePicker；测试 override 为 fake）。
final Provider<PhotoPickerGateway> photoPickerGatewayProvider =
    Provider<PhotoPickerGateway>((ref) => ImagePickerPhotoGateway());

/// 拍照识别服务（D-16）。**当前为远端 stub**：服务端识别端点未实现，
/// 任何输入都返回 RecognitionUnavailable → UI 走手动搜索兜底。
/// 〔待外部确认：第三方食物识别 API 选型 M0 定〕
final Provider<FoodRecognitionService> foodRecognitionServiceProvider =
    Provider<FoodRecognitionService>((ref) {
      return RemoteFoodRecognitionStub(dio: ref.watch(apiDioProvider));
    });

/// 系统 ASR（生产 speech_to_text；测试 override 为 fake）。
final Provider<SpeechGateway> speechGatewayProvider = Provider<SpeechGateway>(
  (ref) => SpeechToTextGateway(),
);

/// 语音轻量解析器（纯 Dart：词典匹配 + 份量正则，D-16）。
final Provider<VoiceTextParser> voiceTextParserProvider =
    Provider<VoiceTextParser>((ref) => const VoiceTextParser());

/// 常吃聚合查询（food_entries ⋈ foods，本地 drift）。
final Provider<FrequentFoodsQuery> frequentFoodsQueryProvider =
    Provider<FrequentFoodsQuery>((ref) {
      return FrequentFoodsQuery(ref.watch(recordRepositoryProvider).db);
    });

/// 常吃 Top N（PRD M3 常吃复用）。
final FutureProvider<List<Food>> recordFrequentFoodsProvider =
    FutureProvider<List<Food>>((ref) {
      final repo = ref.watch(recordRepositoryProvider);
      return ref.watch(frequentFoodsQueryProvider).topFrequent(repo.userId);
    });

// ---- M3 轻量记录（饮水 / 体重，PRD M3 功能点 4） ----

/// 饮水轻量记录仓库（仅本地 drift 口径，〔假设〕不上行同步）。
final Provider<WaterLogRepository> waterLogRepositoryProvider =
    Provider<WaterLogRepository>((ref) {
      return WaterLogRepository(db: ref.watch(appDatabaseProvider));
    });

/// 当日累计饮水量流（毫升，记录页轻量区展示）。
///
/// 数据库未装配（测试/预览仅注入饮食仓储）时降级 0，与
/// `analytics_providers` 的兜底口径一致。
final StreamProvider<int> todayWaterTotalProvider = StreamProvider<int>((ref) {
  try {
    return ref
        .watch(waterLogRepositoryProvider)
        .watchTotalForDate(localDateKey(DateTime.now()));
  } on Object {
    return Stream<int>.value(0);
  }
});

/// 当日体重（kg，来自 M6 WeightLogStore 端口；未记录为 null）。
final FutureProvider<double?> todayWeightProvider = FutureProvider<double?>((
  ref,
) {
  final store = ref.watch(weightLogStoreProvider);
  final key = localDateKey(DateTime.now());
  return store.loadRange(key, key)[key];
});

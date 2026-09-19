import 'dart:async';

import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/food_search_remote.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/frequent_foods.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_asr_service.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_free_text_meal_service.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_label_ocr_service.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:eatwise/features/record/recognition/voice/audio_recorder_gateway.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';
import 'package:eatwise/features/record/recognition/voice/voice_text_parser.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
/// userId 与读取侧（nutrition_data_controller / reports_controller）
/// 同口径取 [currentUserIdProvider]：登录取真实 userId，未登录
/// anonymous；否则登录用户写入落 anonymous、读取按真实 userId 查空
/// （v1.1.1 走查 R2：数据页当日信号灯/7 日趋势恒空）。
final Provider<RecordRepository> recordRepositoryProvider =
    Provider<RecordRepository>((ref) {
      final repo = RecordRepository(
        db: ref.watch(appDatabaseProvider),
        remote: ref.watch(recordRemoteProvider),
        location: tz.local,
        userId: ref.watch(currentUserIdProvider),
      );
      ref.onDispose(() => unawaited(repo.dispose()));
      return repo;
    });

/// 搜索关键词（食物搜索输入框）。
final StateProvider<String> recordSearchQueryProvider = StateProvider<String>(
  (ref) => '',
);

/// 搜索框预填/对焦请求（拍照识别降级对话框的「手动搜索」出口）：
/// 非 null 即请求——非空串预填进搜索框并同步 [recordSearchQueryProvider]，
/// 空串仅对焦；消费方（RecordPage）处理完须复位 null。
final StateProvider<String?> recordSearchPrefillProvider =
    StateProvider<String?>((ref) => null);

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
        waterSync: ref.watch(waterLogSyncProvider),
        customFoodSync: ref.watch(customFoodRepositoryProvider),
        weightSync: ref.watch(weightLogSyncProvider),
        weightStore: ref.watch(weightLogStoreProvider),
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

/// 本次入账选择的餐次（薄荷走查优化点 2；null = 未手动选择，
/// 确认时按当前时间智能预判，入账/关闭结果卡后复位）。
final StateProvider<MealType?> recordMealTypeProvider =
    StateProvider<MealType?>((ref) => null);

/// 今日有效记录流（优化点 2：记录页「今日记录」餐次分组列表数据源）。
final StreamProvider<List<FoodEntry>> todayEntriesProvider =
    StreamProvider<List<FoodEntry>>((ref) {
      final repo = ref.watch(recordRepositoryProvider);
      return repo.db.foodEntryDao.watchEntriesForDate(
        repo.userId,
        localDateKey(DateTime.now()),
      );
    });

/// 记录条目食物查询（今日记录列表行展示食物名用；按 foodId 缓存）。
final FutureProviderFamily<Food?, String> entryFoodProvider =
    FutureProvider.family<Food?, String>((ref, foodId) {
      return ref.watch(recordRepositoryProvider).db.foodDao.getById(foodId);
    });

/// 今日聚合缓存流（本地预估，§2.6；角标注明「待云端校准」）。
final StreamProvider<DailyNutritionCache?> recordTodayNutritionProvider =
    StreamProvider<DailyNutritionCache?>((ref) {
      return ref
          .watch(recordRepositoryProvider)
          .watchDailyNutrition(DateTime.now());
    });

// ---- M3 三入口（拍照识别 / 语音录入 / 常吃复用，PRD M3 / D-16） ----

/// 本次入账的录入方式（四入口各自写入；手动搜索为默认；扫码记见
/// features/record/barcode/）。
final StateProvider<EntrySource> recordEntrySourceProvider =
    StateProvider<EntrySource>((ref) => EntrySource.manual);

/// 结果卡是否标「请确认」（拍照低置信度，PRD M3 异常与边界）。
final StateProvider<bool> recordLowConfidenceProvider = StateProvider<bool>(
  (ref) => false,
);

/// 拍照/相册取图（生产 ImagePicker；测试 override 为 fake）。
final Provider<PhotoPickerGateway> photoPickerGatewayProvider =
    Provider<PhotoPickerGateway>((ref) => ImagePickerPhotoGateway());

/// AI 引擎引导卡「先手动搜索」会话内抑制位（内存态，不持久化：
/// 用户明确选择手动路径后，本次会话各识别入口不再弹引导卡）。
final StateProvider<bool> aiEngineGuideDismissedProvider = StateProvider<bool>(
  (ref) => false,
);

/// 引擎可用性探测函数（默认实现绑 ref：端侧开关开且磁盘就绪，或用户
/// 自配 API 配置完整；装配缺省/插件异常按不可用计，不误判为可用）。
/// 测试 override 注入固定三态。
final Provider<Future<AiEngineAvailability> Function()>
aiEngineAvailabilityFnProvider = Provider((ref) {
  return () async {
    bool onDeviceReady;
    try {
      onDeviceReady =
          ref.read(onDeviceAiEnabledProvider) &&
          await ref.read(onDeviceModelManagerProvider).isReady();
    } on Object {
      onDeviceReady = false;
    }
    bool apiConfigured;
    try {
      final config = (await ref.read(llmConfigStoreProvider).read())
          ?.effective();
      apiConfigured = config != null && config.isComplete;
    } on Object {
      apiConfigured = false;
    }
    return aiEngineAvailabilityOf(
      onDeviceReady: onDeviceReady,
      userApiConfigured: apiConfigured,
    );
  };
});

/// 引导卡路由出口（默认深链 /settings/ai-model——端侧模型卡与自定义
/// API 配置同页；测试 override 断言导航目标，不依赖 go_router 装配）。
final Provider<void Function(BuildContext, AiEngineGuideTarget)>
aiEngineGuideNavigatorProvider = Provider((ref) {
  return (BuildContext context, AiEngineGuideTarget target) =>
      context.push('/settings/ai-model');
});

/// 端侧识别能力是否可用（三服务共用判定：拍照识别/营养表 OCR/自由记/运动
/// 截图识别）：开关开且（快照明确 ready 或快照未出首帧——冷启动窗口期乐观，
/// 真实就绪由服务内部 load 把关：模型真未下载 → load 抛缺失 → 各服务按自身
/// 降级路径处理，与 stub/回落同一兜底）。快照已出且未就绪 → false。
bool onDeviceRecognitionActive(Ref ref) {
  return onDeviceRecognitionActiveFor(
    ref.watch(onDeviceAiEnabledProvider),
    ref.watch(onDeviceModelSnapshotProvider),
  );
}

/// [onDeviceRecognitionActive] 的核心判定（纯函数）：WidgetRef 与 Ref
/// 在 riverpod 2.6 无公共父类，调用侧各自读值后走这里。
bool onDeviceRecognitionActiveFor(
  bool enabled,
  AsyncValue<OnDeviceModelSnapshot> snapshotAsync,
) {
  if (!enabled) return false;
  return switch (snapshotAsync) {
    AsyncData(:final value) => value.status == OnDeviceModelStatus.ready,
    // 快照未出（冷启动 refresh 进行中）：乐观按就绪。
    _ => true,
  };
}

/// 拍照识别服务（D-16）。端侧小模型开关启用且模型已下载 → Gemma4-E2B
/// 视觉识别（[OnDeviceFoodRecognitionService]）；否则保留**远端 stub**
/// （服务端识别端点未实现，任何输入都返回 RecognitionUnavailable → UI
/// 走手动搜索兜底）。〔待外部确认：第三方食物识别 API 选型 M0 定〕
final Provider<FoodRecognitionService> foodRecognitionServiceProvider =
    Provider<FoodRecognitionService>((ref) {
      if (onDeviceRecognitionActive(ref)) {
        final manager = ref.watch(onDeviceModelManagerProvider);
        return OnDeviceFoodRecognitionService(
          gateway: ref.watch(onDeviceLlmGatewayProvider),
          modelPath: manager.modelPath,
          searchFoods: (query) =>
              ref.read(recordRepositoryProvider).searchFoods(query),
        );
      }
      return RemoteFoodRecognitionStub(dio: ref.watch(apiDioProvider));
    });

/// 营养表 OCR 服务（端侧视觉读表）。开关关或快照明确未就绪 → null
/// （表单降级：自定义食物隐藏「拍营养表」入口，条码补录退回纯佐证照）。
final Provider<OnDeviceNutritionLabelOcrService?>
nutritionLabelOcrServiceProvider = Provider((ref) {
  if (!onDeviceRecognitionActive(ref)) return null;
  return OnDeviceNutritionLabelOcrService(
    gateway: ref.watch(onDeviceLlmGatewayProvider),
    modelPath: ref.watch(onDeviceModelManagerProvider).modelPath,
  );
});

/// 自由记文本明细服务（端侧文本推理）。开关关或快照明确未就绪 → null
/// （语音录入回落既有词典解析路径）。
final Provider<OnDeviceFreeTextMealService?> freeTextMealServiceProvider =
    Provider((ref) {
      if (!onDeviceRecognitionActive(ref)) return null;
      final manager = ref.watch(onDeviceModelManagerProvider);
      return OnDeviceFreeTextMealService(
        gateway: ref.watch(onDeviceLlmGatewayProvider),
        modelPath: manager.modelPath,
        searchFoods: (query) =>
            ref.read(recordRepositoryProvider).searchFoods(query),
      );
    });

/// 系统 ASR（生产 speech_to_text；测试 override 为 fake）。
final Provider<SpeechGateway> speechGatewayProvider = Provider<SpeechGateway>(
  (ref) => SpeechToTextGateway(),
);

/// 麦克风录音网关（端侧 ASR 路径；生产 record 插件，测试 override 为 fake）。
final Provider<AudioRecorderGateway> audioRecorderGatewayProvider =
    Provider<AudioRecorderGateway>((ref) {
      final gateway = RecordAudioRecorderGateway();
      ref.onDispose(() => unawaited(gateway.dispose()));
      return gateway;
    });

/// 端侧 ASR 转写服务（系统 ASR 不可用时的回落）。开关关或快照明确未就绪
/// → null（语音入口走引擎引导卡/降级卡）。
final Provider<OnDeviceAsrService?> onDeviceAsrServiceProvider = Provider((
  ref,
) {
  if (!onDeviceRecognitionActive(ref)) return null;
  return OnDeviceAsrService(
    gateway: ref.watch(onDeviceLlmGatewayProvider),
    modelPath: ref.watch(onDeviceModelManagerProvider).modelPath,
  );
});

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

/// 饮水上行同步端（两态 pending/synced，挂 recordSyncEngineProvider 触发链）。
final Provider<RemoteWaterLogSync> waterLogSyncProvider =
    Provider<RemoteWaterLogSync>((ref) {
      return RemoteWaterLogSync(dio: ref.watch(apiDioProvider));
    });

/// 体重推拉同步端（阶段 C：两态 pending/synced，挂 recordSyncEngineProvider 触发链）。
final Provider<RemoteWeightLogSync> weightLogSyncProvider =
    Provider<RemoteWeightLogSync>((ref) {
      return RemoteWeightLogSync(dio: ref.watch(apiDioProvider));
    });

/// 饮水轻量记录仓库（本地落库 pending，经同步引擎上行云端）。
/// userId 与 [recordRepositoryProvider] 同口径（[currentUserIdProvider]），
/// 否则登录用户的饮水记录落 anonymous、趋势按真实 userId 查空。
final Provider<WaterLogRepository> waterLogRepositoryProvider =
    Provider<WaterLogRepository>((ref) {
      return WaterLogRepository(
        db: ref.watch(appDatabaseProvider),
        userId: ref.watch(currentUserIdProvider),
      );
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

/// 当日体重完整条目（含体脂率，录入弹窗预填用；未记录为 null）。
final FutureProvider<WeightLogEntry?> todayWeightEntryProvider =
    FutureProvider<WeightLogEntry?>((ref) {
      final store = ref.watch(weightLogStoreProvider);
      final key = localDateKey(DateTime.now());
      return store.loadEntries(key, key)[key];
    });

/// 当日「断食期用餐」记录条数（阶段 C：记录页今日聚合行标记；0 不展示）。
final StreamProvider<int> todayDuringFastCountProvider = StreamProvider<int>((
  ref,
) {
  try {
    final repo = ref.watch(recordRepositoryProvider);
    return repo.db.foodEntryDao.watchDuringFastCount(
      repo.userId,
      localDateKey(DateTime.now()),
    );
  } on Object {
    return Stream<int>.value(0);
  }
});

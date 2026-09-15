import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_nutrition_estimator.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';

// ==================== Fake ====================

/// 端侧估算源 Fake：可脚本化 就绪/成功（含 dubious）/抛错，记录调用。
final class _FakeOnDeviceSource implements OnDeviceEstimateSource {
  bool ready = true;
  Object? error;
  OnDeviceNutritionEstimate? result = const OnDeviceNutritionEstimate(
    values: OnDeviceNutritionValues(
      kcal: 320,
      proteinG: 5,
      carbsG: 79,
      fatG: 2,
    ),
    dubious: true, // 碳水 >60g，sanity-clamp 命中
  );
  int calls = 0;

  @override
  bool get isPermanentlyDisabled => false;

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

/// 用户自配 API 窄抽象替身（记录调用；ok=false 模拟直连失败）。
final class _FakeUserClient implements UserEstimateSource {
  _FakeUserClient({required this.ok});

  final bool ok;
  int calls = 0;

  static const FoodEstimate sample = FoodEstimate(
    per100g: NutritionSnapshot(kcal: 111, proteinG: 7, carbG: 9, fatG: 3),
    confidence: 'high',
  );

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
    return sample;
  }
}

/// 记录上报批次的埋点通道（record_page_test _RecordingClient 同法）。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    events.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

// ==================== 测试 ====================

/// 自定义食物 AI 估算两级路由 widget 测试：
/// 端侧（开关开且模型就绪）→ 用户自配 API（两级都不可用走「估算暂不可用」提示）；
/// 端侧 dubious 预填 +「估算存疑」提示；端侧失败静默降级；开关关闭/未就绪不走端侧。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late FakeCustomFoodRemote customRemote;
  late RecordRepository repository;
  late _FakeOnDeviceSource onDevice;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    recordRemote = FakeRecordRemote();
    customRemote = FakeCustomFoodRemote();
    repository = RecordRepository(
      db: db,
      remote: recordRemote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    onDevice = _FakeOnDeviceSource();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  Future<void> settleUi(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffolds = find.byType(Scaffold);
    if (scaffolds.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(
        tester.element(scaffolds.first),
      ).hideCurrentSnackBar();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    bool onDeviceEnabled = false,
    UserEstimateSource? userClient,
    LlmConfigStore? llmStore,
    AnalyticsService? analytics,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.onDeviceAiEnabled': onDeviceEnabled,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          waterLogRepositoryProvider.overrideWithValue(
            WaterLogRepository(db: db),
          ),
          customFoodRemoteProvider.overrideWithValue(customRemote),
          llmConfigStoreProvider.overrideWithValue(
            llmStore ?? InMemoryLlmConfigStore(),
          ),
          if (userClient != null)
            userEstimateSourceProvider.overrideWithValue(userClient),
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceEstimateSourceProvider.overrideWithValue(onDevice),
          if (analytics != null)
            analyticsServiceProvider.overrideWithValue(analytics),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openSheetAndEstimate(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('找不到？添加自定义食物'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加自定义食物'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '手工丸子');
    await tester.tap(find.text('AI 估算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String fieldText(WidgetTester tester, int index) {
    return tester
        .widget<TextFormField>(find.byType(TextFormField).at(index))
        .controller!
        .text;
  }

  testWidgets('端侧成功（dubious）：预填 +「端侧估算，请确认」+「估算存疑」提示，埋点 source=ondevice', (
    tester,
  ) async {
    final analyticsClient = _RecordingClient();
    final analytics = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[analyticsClient],
    );
    final userClient = _FakeUserClient(ok: true);
    await pumpPage(
      tester,
      onDeviceEnabled: true,
      userClient: userClient,
      analytics: analytics,
    );

    await openSheetAndEstimate(tester);

    expect(fieldText(tester, 2), '320');
    expect(fieldText(tester, 3), '5');
    expect(fieldText(tester, 4), '79');
    expect(fieldText(tester, 5), '2');
    expect(find.text('端侧估算，请确认'), findsOneWidget);
    expect(find.text('估算存疑，请核对数值'), findsOneWidget);
    expect(onDevice.calls, 1);
    expect(userClient.calls, 0, reason: '端侧命中不再走用户 API');

    await analytics.flush();
    final estimateEvents = analyticsClient.events.where(
      (e) => e.name == 'record_ai_estimate',
    );
    expect(estimateEvents, hasLength(1));
    expect(estimateEvents.single.properties['source'], 'ondevice');
    expect(estimateEvents.single.properties['result'], 'success');
    await settleUi(tester);
  });

  testWidgets('端侧引擎错误 → 静默降级已配置用户 API（常规估算徽标）', (tester) async {
    onDevice.error = const OnDeviceLlmEngineException('推理失败');
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final userClient = _FakeUserClient(ok: true);
    await pumpPage(
      tester,
      onDeviceEnabled: true,
      userClient: userClient,
      llmStore: store,
    );

    await openSheetAndEstimate(tester);

    expect(fieldText(tester, 2), '111');
    expect(find.text('自定义 API 估算，请确认'), findsOneWidget);
    expect(find.text('端侧估算，请确认'), findsNothing);
    expect(onDevice.calls, 1);
    expect(userClient.calls, 1);
    await settleUi(tester);
  });

  testWidgets('端侧失败 + 用户 API 失败 → 估算不可用提示（无服务端兜底），埋点 result=unavailable', (
    tester,
  ) async {
    onDevice.error = const OnDeviceLlmEngineException('推理失败');
    final analyticsClient = _RecordingClient();
    final analytics = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[analyticsClient],
    );
    final store = InMemoryLlmConfigStore();
    await store.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    final userClient = _FakeUserClient(ok: false);
    await pumpPage(
      tester,
      onDeviceEnabled: true,
      userClient: userClient,
      llmStore: store,
      analytics: analytics,
    );

    await openSheetAndEstimate(tester);

    expect(find.text('估算暂不可用，请手动填写'), findsOneWidget);
    expect(find.text('自定义 API 估算，请确认'), findsNothing);
    expect(find.text('端侧估算，请确认'), findsNothing);
    expect(onDevice.calls, 1);
    expect(userClient.calls, 1);

    await analytics.flush();
    final estimateEvents = analyticsClient.events.where(
      (e) => e.name == 'record_ai_estimate',
    );
    expect(estimateEvents, hasLength(1));
    expect(estimateEvents.single.properties['source'], 'none');
    expect(estimateEvents.single.properties['result'], 'unavailable');
    await settleUi(tester);
  });

  testWidgets('开关关闭 → 不走端侧（端侧零调用）；未配置 API → 估算不可用提示', (tester) async {
    await pumpPage(tester, onDeviceEnabled: false);

    await openSheetAndEstimate(tester);

    expect(find.text('估算暂不可用，请手动填写'), findsOneWidget);
    expect(onDevice.calls, 0);
    await settleUi(tester);
  });

  testWidgets('开关开但模型未就绪 → 不走端侧不触发下载；未配置 API → 估算不可用提示', (tester) async {
    onDevice.ready = false;
    await pumpPage(tester, onDeviceEnabled: true);

    await openSheetAndEstimate(tester);

    expect(find.text('估算暂不可用，请手动填写'), findsOneWidget);
    expect(onDevice.calls, 0);
    await settleUi(tester);
  });
}

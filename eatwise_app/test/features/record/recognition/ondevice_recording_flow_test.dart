import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_asr_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 端侧录音转写流程 widget 测试（系统 ASR 不可用设备：无 GMS ROM）：
/// 端侧就绪 → 录音面板（开始/停止/转写/回填/完成入账）；权限拒绝 →
/// 降级卡；模型未就绪且无云端 API → 引擎引导卡；引导被会话抑制 →
/// 降级卡；转写失败 → 面板错误态可重录。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakeSpeechGateway speechGateway;
  late FakeAudioRecorderGateway recorderGateway;
  late _FakeGateway gateway;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.getLocation('Asia/Shanghai'),
    );
    speechGateway = FakeSpeechGateway()..available = false; // 模拟无 GMS 设备
    recorderGateway = FakeAudioRecorderGateway();
    gateway = _FakeGateway()..audioResponse = '一碗米饭';
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

  /// 泵页：端侧开关/快照/ASR 服务/录音网关按参数注入。
  Future<void> pumpPage(
    WidgetTester tester, {
    required bool onDeviceReady,
    bool guideDismissed = false,
    bool transcribeFails = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.onDeviceAiEnabled': onDeviceReady,
    });
    final prefs = await SharedPreferences.getInstance();
    gateway.audioResponse = transcribeFails ? '「」' : '一碗米饭';
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceModelSnapshotProvider.overrideWith(
            (ref) => Stream<OnDeviceModelSnapshot>.value(
              OnDeviceModelSnapshot(
                status: onDeviceReady
                    ? OnDeviceModelStatus.ready
                    : OnDeviceModelStatus.notDownloaded,
              ),
            ),
          ),
          speechGatewayProvider.overrideWithValue(speechGateway),
          audioRecorderGatewayProvider.overrideWithValue(recorderGateway),
          onDeviceAsrServiceProvider.overrideWithValue(
            OnDeviceAsrService(
              gateway: gateway,
              modelPath: () async => '/fake/gemma4-e2b.litertlm',
            ),
          ),
          // 自由记服务置 null：本组测试聚焦 ASR 路径，转写文本走词典兜底。
          freeTextMealServiceProvider.overrideWithValue(null),
          if (guideDismissed)
            aiEngineGuideDismissedProvider.overrideWith((ref) => true),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('端侧就绪：录音面板开始/停止 → 转写回填可编辑 → 完成走词典入账', (tester) async {
    await pumpPage(tester, onDeviceReady: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 面板打开：初始引导「点一下开始说话」（状态文本区 + 主按钮各一处）。
    expect(find.text('点一下开始说话'), findsNWidgets(2));
    // 权限已在流程层申请（fake 授予）。
    expect(recorderGateway.permitted, isTrue);

    // 开始录音（锁定主按钮，文本区同名文案不算）。
    await tester.tap(find.widgetWithText(OutlinedButton, '点一下开始说话'));
    await tester.pump();
    expect(recorderGateway.recording, isTrue);
    // 状态文本区 + 主按钮各一处。
    expect(find.text('正在录音… 再点一下停止'), findsNWidgets(2));

    // 停止 → 转写 → 回填可编辑文本框（锁定主按钮，状态文本区同名不算）。
    await tester.tap(find.widgetWithText(OutlinedButton, '正在录音… 再点一下停止'));
    await tester.pump();
    // 「转写中…」为过渡态（fake 网关即时完成），不断言该瞬态。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '一碗米饭');

    // 完成 → 词典解析兜底入账预填（白米饭 200g，「一碗」映射）。
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('确认记录'), findsOneWidget);
    // 结果卡标题 + 底部搜索列表同名食物各一处。
    expect(find.text('白米饭'), findsNWidgets(2));
    await settleUi(tester);
  });

  testWidgets('录音权限拒绝 → 现有降级卡（不弹端侧面板）', (tester) async {
    recorderGateway.permitted = false;
    await pumpPage(tester, onDeviceReady: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('麦克风未授权'), findsOneWidget);
    expect(find.text('点一下开始说话'), findsNothing); // 录音面板未打开
    await settleUi(tester);
  });

  testWidgets('模型未就绪且无云端 API → 引擎引导卡（不复读降级卡）', (tester) async {
    await pumpPage(tester, onDeviceReady: false);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('AI 识别需要一个模型'), findsOneWidget);
    expect(find.text('下载本地模型（推荐）'), findsOneWidget);
    expect(find.text('配置云端 API'), findsOneWidget);
    expect(find.text('先手动搜索'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('引导卡被会话抑制 → 落回现有降级卡', (tester) async {
    await pumpPage(tester, onDeviceReady: false, guideDismissed: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('AI 识别需要一个模型'), findsNothing);
    expect(find.textContaining('用不了语音识别'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('转写失败 → 面板错误态，可再录（不静默退出）', (tester) async {
    await pumpPage(tester, onDeviceReady: true, transcribeFails: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(OutlinedButton, '点一下开始说话'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '正在录音… 再点一下停止'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 错误态文案 + 面板仍在（可重录）。
    // 状态文本区 + 错误提示区（红字）各一处。
    expect(find.text('没转写出来，再录一次，或点右边键盘图标打字'), findsNWidgets(2));
    // 主按钮回到 idle 引导（可重录）。
    expect(find.text('点一下开始说话'), findsOneWidget);
    await settleUi(tester);
  });
}

/// 推理网关 Fake（音频路径）。
final class _FakeGateway implements OnDeviceLlmGateway {
  String audioResponse = '';
  int loadCalls = 0;
  bool loaded = false;
  bool vision = false;
  bool audio = false;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  bool get audioEnabled => loaded && audio;

  @override
  Future<void> load(
    String modelPath, {
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
    loadCalls++;
    loaded = true;
    vision = enableVision;
    audio = enableAudio;
  }

  @override
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    throw UnimplementedError('本测试不走文本推理');
  }

  @override
  Future<String> inferWithImage(
    String prompt,
    Uint8List imageBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    throw UnimplementedError('本测试不走视觉推理');
  }

  @override
  Future<String> inferWithAudio(
    String prompt,
    Uint8List wavBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) async {
    return audioResponse;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
    audio = false;
  }
}

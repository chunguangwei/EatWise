import 'dart:async';
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
import 'package:eatwise/features/record/recognition/presentation/ondevice_recording_sheet.dart';
import 'package:eatwise/features/record/recognition/presentation/voice_model_download_sheet.dart';
import 'package:eatwise/features/settings/presentation/ondevice_model_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 系统 ASR 设备级记忆 + 精简语音兜底链路 widget 测试：
/// 致命错误/静默 6s 写记忆（prefs）→ 之后点语音记直达端侧（就绪进录音
/// 面板 / 未就绪直接引导卡）→ 引导卡内嵌下载带进度 → 完成自动回录音
/// 面板；端侧转写失败自动重置记忆。
void main() {
  const brokenKey = 'settings.systemAsrBroken';

  late AppDatabase db;
  late RecordRepository repository;
  late FakeSpeechGateway speechGateway;
  late FakeAudioRecorderGateway recorderGateway;
  late _FakeGateway gateway;
  late _FakeActions actions;
  late StreamController<OnDeviceModelSnapshot> snapshots;
  late SharedPreferences prefs;

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
    speechGateway = FakeSpeechGateway(); // 系统 ASR 可用（初始化 true）
    recorderGateway = FakeAudioRecorderGateway();
    gateway = _FakeGateway()..audioResponse = '一碗米饭';
    actions = _FakeActions();
    snapshots = StreamController<OnDeviceModelSnapshot>.broadcast();
    addTearDown(() async {
      await snapshots.close();
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

  /// 泵页：broken 记忆/端侧就绪/快照流/下载动作 按参数注入。
  Future<void> pumpPage(
    WidgetTester tester, {
    required bool broken,
    required bool onDeviceReady,
    bool guideDismissed = false,
    bool transcribeFails = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      brokenKey: broken,
      'settings.onDeviceAiEnabled': onDeviceReady,
    });
    prefs = await SharedPreferences.getInstance();
    gateway.audioResponse = transcribeFails ? '「」' : '一碗米饭';
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceModelSnapshotProvider.overrideWith((ref) => snapshots.stream),
          onDeviceModelActionsProvider.overrideWithValue(actions),
          speechGatewayProvider.overrideWithValue(speechGateway),
          audioRecorderGatewayProvider.overrideWithValue(recorderGateway),
          onDeviceAsrServiceProvider.overrideWithValue(
            OnDeviceAsrService(
              gateway: gateway,
              modelPath: () async => '/fake/gemma4-e2b.litertlm',
            ),
          ),
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

  /// 打开系统听写面板（broken=false 路径）。
  Future<void> openListeningSheet(WidgetTester tester) async {
    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  void emitSnapshot(
    OnDeviceModelStatus status, {
    int downloaded = 0,
    int total = 100,
  }) {
    snapshots.add(
      OnDeviceModelSnapshot(
        status: status,
        downloadedBytes: downloaded,
        totalBytes: total,
      ),
    );
  }

  testWidgets('致命 ASR 错误 → 写设备级「系统 ASR 已坏」记忆（prefs）', (tester) async {
    await pumpPage(tester, broken: false, onDeviceReady: true);
    await openListeningSheet(tester);

    speechGateway.onError!('error_network');
    await tester.pump();

    expect(prefs.getBool(brokenKey), isTrue);
    await settleUi(tester);
  });

  testWidgets('6s 静默兜底 → 写设备级「系统 ASR 已坏」记忆', (tester) async {
    await pumpPage(tester, broken: false, onDeviceReady: true);
    await openListeningSheet(tester);

    await tester.pump(const Duration(seconds: 6));

    expect(prefs.getBool(brokenKey), isTrue);
    await settleUi(tester);
  });

  testWidgets('记忆设备 + 端侧就绪 → 点语音记直接进录音面板（不等 6s、不走系统听写）', (tester) async {
    emitSnapshot(OnDeviceModelStatus.ready);
    await pumpPage(tester, broken: true, onDeviceReady: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 直接进端侧录音面板：状态区 + 主按钮「点一下开始说话」；
    // 系统听写面板（「正在听…」）未出现。
    expect(find.text('点一下开始说话'), findsNWidgets(2));
    expect(find.text('正在听… 说说吃了什么，如「一碗米饭」'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('记忆设备 + 模型未下载 → 点语音记直接弹引擎引导卡（不开系统听写）', (tester) async {
    await pumpPage(tester, broken: true, onDeviceReady: false);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 识别需要一个模型'), findsOneWidget);
    expect(find.text('下载本地模型（推荐）'), findsOneWidget);
    expect(find.text('正在听… 说说吃了什么，如「一碗米饭」'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('引导卡点下载 → 内嵌下载带进度 → 就绪自动回端侧录音面板', (tester) async {
    await pumpPage(tester, broken: true, onDeviceReady: false);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('下载本地模型（推荐）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 内嵌下载弹层（不跳设置页）：标题 + 已开始下载。
    expect(find.byType(VoiceModelDownloadSheet), findsOneWidget);
    expect(find.text('下载离线模型'), findsOneWidget);
    expect(actions.ensureCalls, 1);

    // 下载中 → 进度文案。
    emitSnapshot(OnDeviceModelStatus.downloading, downloaded: 50);
    await tester.pump();
    expect(find.text('下载中 50%'), findsOneWidget);

    // 就绪 → 弹层自动关 → 直接进端侧录音面板（顺畅回到语音）。
    emitSnapshot(OnDeviceModelStatus.ready);
    await tester.pump();
    // 下载弹层退出动画（生产侧 pop 后延迟 300ms 再开录音面板）。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    for (final e in find.byType(VoiceModelDownloadSheet).evaluate()) {
      final route = ModalRoute.of(e);
      debugPrint('route=${route?.runtimeType} isCurrent=${route?.isCurrent}');
    }
    debugPrint(
      'recSheet=${find.byType(OnDeviceRecordingSheet).evaluate().length} '
      'texts=${find.byType(Text).evaluate().length}',
    );
    expect(find.byType(VoiceModelDownloadSheet), findsNothing);
    expect(find.text('点一下开始说话'), findsNWidgets(2));
    await settleUi(tester);
  });

  testWidgets('端侧转写失败 → 自动重置「系统 ASR 已坏」记忆（恢复途径）', (tester) async {
    emitSnapshot(OnDeviceModelStatus.ready);
    await pumpPage(
      tester,
      broken: true,
      onDeviceReady: true,
      transcribeFails: true,
    );

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 直接进录音面板 → 录 → 停 → 转写失败。
    await tester.tap(find.widgetWithText(OutlinedButton, '点一下开始说话'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '正在录音… 再点一下停止'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 错误态出现，且记忆被重置（下次回系统路径再试）。
    expect(find.text('没转写出来，再录一次，或点右边键盘图标打字'), findsWidgets);
    expect(prefs.getBool(brokenKey), isFalse);
    await settleUi(tester);
  });

  // 安卓真机走查 bug（无 GMS/鸿蒙设备 systemAsrBroken=true 直达端侧路径）：
  // 录音面板点「完成」pop 出的 VoiceTranscript 曾被 startVoiceInput 的
  // broken 分支丢弃，从不进 _handleTranscript → 无 AI 检测无记录。
  testWidgets('记忆设备直达端侧：录音转写后点完成 → 进明细确认卡（transcript 不被丢弃）', (tester) async {
    emitSnapshot(OnDeviceModelStatus.ready);
    await pumpPage(tester, broken: true, onDeviceReady: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 直达录音面板 → 录 → 停 → 转写回填。
    await tester.tap(find.widgetWithText(OutlinedButton, '点一下开始说话'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '正在录音… 再点一下停止'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 完成 → 必须进管线（自由记服务被 override 为 null → 词典兜底），
    // 断言明细确认弹层出现；修复前 transcript 被扔，面板直接消失。
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('确认这餐明细'), findsOneWidget);
    expect(find.text('白米饭'), findsWidgets);
    await settleUi(tester);
  });
}

/// 下载动作 Fake（复用设置页卡片测试同款 seam）。
final class _FakeActions implements OnDeviceModelActions {
  int ensureCalls = 0;
  int cancelCalls = 0;

  @override
  Future<String> ensureModel() {
    ensureCalls++;
    return Future<String>.value('/fake/model.litertlm');
  }

  @override
  void cancel() {
    cancelCalls++;
  }

  @override
  Future<void> delete() async {}

  @override
  bool get estimatePermanentlyDisabled => false;
}

/// 推理网关 Fake（音频路径）。
final class _FakeGateway implements OnDeviceLlmGateway {
  String audioResponse = '';
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
    double? topP,
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
    double? topP,
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
    double? topP,
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

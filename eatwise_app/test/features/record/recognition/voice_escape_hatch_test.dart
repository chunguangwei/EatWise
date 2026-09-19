import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_asr_service.dart';
import 'package:eatwise/features/record/recognition/presentation/ondevice_recording_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 听写面板逃生舱 widget 测试：致命 ASR 错误 / 6s 静默兜底 + 端侧 ASR
/// 就绪 → 「用离线小模型识别」按钮，点了取消系统听写并进端侧录音面板；
/// 端侧未就绪 / 良性错误（没听清）→ 不出现按钮（现状保持）。
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
    speechGateway = FakeSpeechGateway(); // 系统 ASR 可用（初始化 true）
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

  Future<void> pumpPage(WidgetTester tester, {required bool asrReady}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          speechGatewayProvider.overrideWithValue(speechGateway),
          audioRecorderGatewayProvider.overrideWithValue(recorderGateway),
          onDeviceAsrServiceProvider.overrideWithValue(
            asrReady
                ? OnDeviceAsrService(
                    gateway: gateway,
                    modelPath: () async => '/fake/gemma4-e2b.litertlm',
                  )
                : null,
          ),
          // 自由记服务置 null：本组聚焦逃生舱切换，转写文本走词典兜底。
          freeTextMealServiceProvider.overrideWithValue(null),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 打开听写面板（含滑入动画）。
  Future<void> openListeningSheet(WidgetTester tester) async {
    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('致命错误 + 端侧就绪 → 按钮出现，点了取消系统听写并进端侧面板', (tester) async {
    await pumpPage(tester, asrReady: true);
    await openListeningSheet(tester);

    speechGateway.onError!('error_network');
    await tester.pump();

    expect(find.text('用离线小模型识别'), findsOneWidget);

    await tester.tap(find.text('用离线小模型识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 系统听写已取消；端侧录音面板覆盖打开（外层听写面板留在树下层，
    // 端侧面板返回后由它透传结果并关闭——见 _switchToOnDevice）。
    expect(speechGateway.cancelled, isTrue);
    expect(find.text('点一下开始说话'), findsNWidgets(2)); // 状态区 + 主按钮
    await settleUi(tester);
  });

  testWidgets('致命错误 + 端侧未就绪 → 不出现按钮（现状保持）', (tester) async {
    await pumpPage(tester, asrReady: false);
    await openListeningSheet(tester);

    speechGateway.onError!('error_network');
    await tester.pump();

    expect(find.text('语音识别不可用，点右边键盘图标打字输入'), findsOneWidget);
    expect(find.text('用离线小模型识别'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('良性错误（没听清）+ 端侧就绪 → 不出现按钮（重说即可）', (tester) async {
    await pumpPage(tester, asrReady: true);
    await openListeningSheet(tester);

    speechGateway.onError!('error_no_match');
    await tester.pump();

    expect(find.text('没听清，请再说一次，或点右边键盘图标打字'), findsOneWidget);
    expect(find.text('用离线小模型识别'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('6s 静默兜底 + 端侧就绪 → 按钮出现', (tester) async {
    await pumpPage(tester, asrReady: true);
    await openListeningSheet(tester);

    await tester.pump(const Duration(seconds: 6));

    expect(find.text('没听清，请再说一次，或点右边键盘图标打字'), findsOneWidget);
    expect(find.text('用离线小模型识别'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('端侧面板取消 → 整个语音流程静默关闭（不留死面板）', (tester) async {
    await pumpPage(tester, asrReady: true);
    await openListeningSheet(tester);

    speechGateway.onError!('error_network');
    await tester.pump();
    await tester.tap(find.text('用离线小模型识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('点一下开始说话'), findsNWidgets(2));

    // 端侧面板点取消（外层听写面板仍在树下层，须在端侧面板内消歧）→
    // 两层都关，回到记录页。
    await tester.tap(
      find.descendant(
        of: find.byType(OnDeviceRecordingSheet),
        matching: find.text('取消'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('点一下开始说话'), findsNothing);
    expect(find.text('语音记'), findsOneWidget);
    expect(recorderGateway.cancelled, isFalse); // 未在录音，无需取消
    await settleUi(tester);
  });
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

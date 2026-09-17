import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_free_text_meal_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 一句话自由记 widget 测试（语音/键盘同构）：ASR 文本 → 端侧文本明细
/// 推理 → 明细确认卡（EntrySource.voice，无「重新拍摄」）→ 全部入账；
/// 端侧不可用回落词典解析（既有路径回归）。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late RecordRepository repository;
  late FakeSpeechGateway speechGateway;
  late _FakeGateway gateway;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    recordRemote = FakeRecordRemote();
    repository = RecordRepository(
      db: db,
      remote: recordRemote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    speechGateway = FakeSpeechGateway();
    gateway = _FakeGateway();
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

  /// 弹层内查找（页底搜索列表有同名食物，须在 BottomSheet 内消歧）。
  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  Future<void> pumpPage(WidgetTester tester, {required bool freeText}) async {
    // 放大测试屏幕：明细弹层字段多，默认尺寸按钮不可点。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          speechGatewayProvider.overrideWithValue(speechGateway),
          if (freeText)
            freeTextMealServiceProvider.overrideWithValue(
              OnDeviceFreeTextMealService(
                gateway: gateway,
                modelPath: () async => '/fake/gemma4-e2b.litertlm',
                searchFoods: repository.searchFoods,
              ),
            ),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 语音记 → 注入 ASR 文本 → 完成 → 等明细卡落地（含滑入动画）。
  Future<void> speakAndFinish(WidgetTester tester, String text) async {
    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    speechGateway.onText!(text);
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('语音自由记：明细卡逐条确认 → 全部入账（EntrySource.voice）', (tester) async {
    gateway.textResponse =
        '白米饭 => rice => 200 => 116 => 2.6 => 25.9 => 0.3\n'
        '鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8';
    await pumpPage(tester, freeText: true);

    await speakAndFinish(tester, '中午吃了一碗米饭加个蛋');

    // 明细卡：两条（库内规范名），无「重新拍摄」（文本场景）。
    expect(inSheet(find.text('确认这餐明细')), findsOneWidget);
    expect(inSheet(find.text('白米饭')), findsOneWidget);
    expect(inSheet(find.text('鸡蛋')), findsOneWidget);
    expect(inSheet(find.text('重新拍摄')), findsNothing);
    expect(inSheet(find.textContaining('热量 232 千卡')), findsOneWidget);

    recordRemote.mode = FakeRemoteMode.offline; // 只落 pending
    await tester.tap(inSheet(find.text('全部记录')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('已记录 2 条'), findsOneWidget);
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.source == EntrySource.voice), isTrue);
    expect(entries.map((e) => e.amountG), containsAll(<double>[200, 50]));
    await settleUi(tester);
  });

  testWidgets('键盘输入路径：听写面板切键盘 → 同构推理入账', (tester) async {
    gateway.textResponse = '白米饭 => rice => 200 => 116 => 2.6 => 25.9 => 0.3';
    await pumpPage(tester, freeText: true);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 切换键盘输入并键入一句话。
    await tester.tap(find.byTooltip('键盘输入'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '一碗米饭');
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(inSheet(find.text('确认这餐明细')), findsOneWidget);
    expect(inSheet(find.text('白米饭')), findsOneWidget);

    recordRemote.mode = FakeRemoteMode.offline;
    await tester.tap(inSheet(find.text('全部记录')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries, hasLength(1));
    expect(entries.single.source, EntrySource.voice);
    await settleUi(tester);
  });

  testWidgets('端侧推理失败 → 回落词典解析（既有路径不破坏）', (tester) async {
    gateway.inferError = const OnDeviceLlmEngineException('推理失败');
    await pumpPage(tester, freeText: true);

    await speakAndFinish(tester, '一碗米饭');

    // 回落词典解析：结果卡预填白米饭 200g（「一碗」映射），可直接确认。
    expect(find.text('确认记录'), findsOneWidget);
    expect(inSheet(find.text('确认这餐明细')), findsNothing);
    expect(find.textContaining('热量 232 千卡'), findsOneWidget);
    await settleUi(tester);
  });
}

/// 推理网关 Fake（本文件只走文本推理）。
final class _FakeGateway implements OnDeviceLlmGateway {
  bool loaded = false;
  bool vision = false;
  String textResponse = '';
  Object? inferError;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  Future<void> load(String modelPath, {bool enableVision = false}) async {
    loaded = true;
    vision = enableVision;
  }

  @override
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) async {
    final error = inferError;
    if (error != null) throw error;
    return textResponse;
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
    throw UnimplementedError('本测试只走文本推理');
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}

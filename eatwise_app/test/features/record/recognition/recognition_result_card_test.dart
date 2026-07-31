import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 识别结果卡 widget 测试（PRD M3：可编辑识别结果卡）。
///
/// 覆盖：拍照低置信度标「请确认」+ 份量实时重算 + 确认入账（source 正确）、
/// 识别中取消不丢已输入内容、识别不可用走手动搜索兜底、
/// 语音解析预填共用同一结果卡、常吃复用点选即填充。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late RecordRepository repository;
  late FakePhotoPickerGateway photoGateway;
  late FakeFoodRecognitionService recognitionService;
  late FakeSpeechGateway speechGateway;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    repository = RecordRepository(
      db: db,
      remote: remote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    photoGateway = FakePhotoPickerGateway();
    recognitionService = FakeFoodRecognitionService();
    speechGateway = FakeSpeechGateway();
    // 见 record_page_test：drift 流退订清理依赖真实事件区。
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

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(speechGateway),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 走一遍「拍照记 → 拍照」，识别完成后结果卡应已填充。
  Future<void> pickPhotoAndRecognize(WidgetTester tester) async {
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('拍照识别成功：低置信度标「请确认」，份量重算，确认入账 photo', (tester) async {
    final rice = (await db.foodDao.getById('f-rice'))!;
    recognitionService.outcome = RecognitionSuccess(<RecognizedCandidate>[
      RecognizedCandidate(food: rice, defaultAmountG: 150, confidence: 0.5),
    ]);
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    // 结果卡：预填识别份量 + 低置信度标记 + 营养按 150g 实时换算。
    expect(find.text('请确认'), findsOneWidget);
    expect(find.text('确认记录'), findsOneWidget);
    expect(find.text('热量 174 千卡'), findsOneWidget);
    final amountField = tester.widget<TextField>(find.byType(TextField).last);
    expect(amountField.controller!.text, '150');

    // 份量修改 → 营养实时重算（US-3.1）。
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);

    // 确认入账：乐观更新吐司 + source = photo。
    // 切离线确认：只落 pending（不启动 10s 上行计时器，测试假时钟不受扰）。
    remote.mode = FakeRemoteMode.offline;
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries, hasLength(1));
    expect(entries.single.source, EntrySource.photo);
    expect(entries.single.amountG, 200);
    await settleUi(tester);
  });

  testWidgets('识别中取消：不填结果卡、不丢已输入的搜索词', (tester) async {
    recognitionService.completer = Completer<RecognitionOutcome>();
    await pumpPage(tester);

    // 先输入搜索词（用户已输入内容）。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 拍照 → 识别中对话框出现 → 取消。
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识别中…'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识别中…'), findsNothing);

    // 识别随后完成：结果被丢弃，不填卡；搜索词原样保留。
    recognitionService.completer!.complete(
      const RecognitionUnavailable('network'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认记录'), findsNothing);
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.controller!.text, '米饭');
    await settleUi(tester);
  });

  testWidgets('识别不可用（stub/无网络）→ 提示手动搜索兜底', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable('network');
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);
    expect(find.text('暂时识别不了，手动搜索一样快'), findsOneWidget);
    expect(find.text('确认记录'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('语音录入：解析预填共用结果卡，确认入账 voice', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('正在听'), findsOneWidget);

    // 模拟系统 ASR 回传 → 实时回显 → 完成。
    speechGateway.onText!('一碗米饭');
    await tester.pump();
    expect(find.text('一碗米饭'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 结果卡预填：白米饭 200g（一碗映射）；语音不标「请确认」。
    expect(find.text('确认记录'), findsOneWidget);
    expect(find.text('请确认'), findsNothing);
    expect(find.text('热量 232 千卡'), findsOneWidget);

    remote.mode = FakeRemoteMode.offline;
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries.single.source, EntrySource.voice);
    expect(entries.single.amountG, 200);
    await settleUi(tester);
  });

  testWidgets('常吃复用：历史高频点选即填充，确认入账 frequent', (tester) async {
    // 造历史：米饭 ×2、鸡蛋 ×1（离线模式避免上行计时器）。
    remote.mode = FakeRemoteMode.offline;
    final rice = (await db.foodDao.getById('f-rice'))!;
    final egg = (await db.foodDao.getById('f-egg'))!;
    for (var i = 0; i < 2; i++) {
      await repository.addEntry(
        RecordDraft(
          foodId: rice.id,
          amountG: 100,
          mealUtc: DateTime.now().toUtc(),
          source: EntrySource.manual,
        ),
      );
    }
    await repository.addEntry(
      RecordDraft(
        foodId: egg.id,
        amountG: 100,
        mealUtc: DateTime.now().toUtc(),
        source: EntrySource.manual,
      ),
    );

    await pumpPage(tester);
    await tester.tap(find.text('常吃'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('常吃的食物'), findsOneWidget);

    // 高频第一 = 白米饭；点选即填充结果卡（份量留空必填）。
    // 注意底部搜索列表也展示「白米饭」，须在 sheet 内消歧。
    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('白米饭')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认记录'), findsOneWidget);
    expect(find.text('热量 116 千卡'), findsNothing); // 份量必填：不再默认预览 100g

    // 空份量点确认 → 拦截提示，不入账。
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入大于 0 的份量'), findsOneWidget);
    expect((await repository.entriesForDate(DateTime.now().toUtc())).length, 3);

    // 输入份量后确认入账（frequent 来源）。
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries.last.source, EntrySource.frequent);
    await settleUi(tester);
  });
}

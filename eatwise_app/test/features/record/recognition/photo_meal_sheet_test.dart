import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
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

/// 拍照识别明细确认弹层 widget 测试（多行明细协议 UI）。
///
/// 覆盖：组合餐多条明细（克数预填/营养实时换算/删除）、库未命中条目
/// 标记并在入账时自动建自定义食物、全部记录生成多条 entry（photo 来源）、
/// 重新拍摄入口、全部删除后禁用入账。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late RecordRepository repository;
  late FakePhotoPickerGateway photoGateway;
  late FakeFoodRecognitionService recognitionService;
  late FakeCustomFoodRemote customRemote;

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
    photoGateway = FakePhotoPickerGateway();
    recognitionService = FakeFoodRecognitionService();
    customRemote = FakeCustomFoodRemote();
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
    double width = 1080,
    double height = 2400,
  }) async {
    // 放大测试屏幕：明细弹层字段多，默认尺寸按钮不可点。
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(FakeSpeechGateway()),
          customFoodRemoteProvider.overrideWithValue(customRemote),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 弹层内查找（页底搜索列表也展示同名食物，须在 BottomSheet 内消歧，
  /// 与常吃复用测试同法）。
  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  /// 走一遍「拍照记 → 拍照」，等待识别结果落地。
  Future<void> pickPhotoAndRecognize(WidgetTester tester) async {
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    // 明细弹层滑入动画完成后再操作（加载框关闭链是异步的，
    // 少一拍弹层还在屏外，tap 会 miss）。
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 组合餐识别结果：米饭/鸡蛋命中库（种子数据），薯片库未命中。
  Future<RecognitionSuccess> comboOutcome() async {
    final rice = (await db.foodDao.getById('f-rice'))!;
    final egg = (await db.foodDao.getById('f-egg'))!;
    return RecognitionSuccess(<RecognizedMealItem>[
      RecognizedMealItem(
        name: rice.nameZh,
        nameEn: rice.nameEn,
        grams: 200,
        per100g: const NutritionSnapshot(
          kcal: 116,
          proteinG: 2.6,
          carbG: 25.9,
          fatG: 0.3,
        ),
        confidence: 0.85,
        food: rice,
      ),
      RecognizedMealItem(
        name: egg.nameZh,
        nameEn: egg.nameEn,
        grams: 50,
        per100g: const NutritionSnapshot(
          kcal: 144,
          proteinG: 13.3,
          carbG: 2.8,
          fatG: 8.8,
        ),
        confidence: 0.85,
        food: egg,
      ),
      const RecognizedMealItem(
        name: '薯片',
        nameEn: 'potato chips',
        grams: 60,
        per100g: NutritionSnapshot(kcal: 536, proteinG: 7, carbG: 53, fatG: 32),
        confidence: 0.4, // 库未命中必低置信
      ),
    ]);
  }

  testWidgets('组合餐明细卡：三条明细，克数预填 + 营养实时换算 + 未命中标记', (tester) async {
    recognitionService.outcome = await comboOutcome();
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    expect(inSheet(find.text('确认这餐明细')), findsOneWidget);
    expect(inSheet(find.text('白米饭')), findsOneWidget);
    expect(inSheet(find.text('鸡蛋')), findsOneWidget);
    expect(inSheet(find.text('薯片')), findsOneWidget);
    // 库未命中条目标记 + 低置信「请确认」。
    expect(inSheet(find.text('库未收录，将自动新建')), findsOneWidget);
    expect(inSheet(find.text('请确认')), findsOneWidget);
    // 克数预填（模型估份量；弹层内三个克数输入框）。
    final gramsFields = tester
        .widgetList<TextField>(inSheet(find.byType(TextField)))
        .toList();
    expect(gramsFields.map((f) => f.controller!.text), <String>[
      '200',
      '50',
      '60',
    ]);
    // 营养按克数换算（白米饭 200g：116×2=232 千卡；薯片 60g：322 千卡）。
    expect(inSheet(find.textContaining('热量 232 千卡')), findsOneWidget);
    expect(inSheet(find.textContaining('热量 322 千卡')), findsOneWidget);

    // 改克数 → 营养实时重算（白米饭 200 → 300：348 千卡）。
    await tester.enterText(inSheet(find.byType(TextField)).first, '300');
    await tester.pump();
    expect(inSheet(find.textContaining('热量 348 千卡')), findsOneWidget);

    await settleUi(tester);
  });

  testWidgets('删除条目 + 全部记录：入账仅保留条目，多条 entry 均 photo 来源', (tester) async {
    recognitionService.outcome = await comboOutcome();
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);
    expect(inSheet(find.text('鸡蛋')), findsOneWidget);

    // 删掉鸡蛋行（弹层内三行各有关闭按钮，取第二行）。
    await tester.tap(inSheet(find.byIcon(Icons.close)).at(1));
    await tester.pump();
    expect(inSheet(find.text('鸡蛋')), findsNothing);

    // 全部记录：白米饭（库内）+ 薯片（自动建自定义食物）。
    recordRemote.mode = FakeRemoteMode.offline; // 只落 pending
    await tester.tap(find.text('全部记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('已记录 2 条'), findsOneWidget);
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.source == EntrySource.photo), isTrue);
    expect(entries.map((e) => e.amountG), containsAll(<double>[200, 60]));

    // 薯片已自动建成自定义食物（模型估值入库，isCustom）。
    final saved = await db.foodDao.searchFoods('薯片');
    expect(saved, hasLength(1));
    expect(saved.single.isCustom, isTrue);
    expect(saved.single.kcalPer100g, 536);
    expect(entries.map((e) => e.foodId), contains(saved.single.id));
    await settleUi(tester);
  });

  testWidgets('明细卡「重新拍摄」：关闭弹层并重新拉起来源选择', (tester) async {
    recognitionService.outcome = await comboOutcome();
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);
    expect(find.text('确认这餐明细'), findsOneWidget);

    await tester.tap(inSheet(find.text('重新拍摄')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('确认这餐明细'), findsNothing);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);

    // 走完第二遍（重拍已直接拉起来源选择：拍照 → 明细卡再现 → 取消关闭），
    // 不留悬挂路由。
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(inSheet(find.text('确认这餐明细')), findsOneWidget);
    await tester.tap(inSheet(find.text('取消')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认这餐明细'), findsNothing);
    expect((await repository.entriesForDate(DateTime.now().toUtc())), isEmpty);
    await settleUi(tester);
  });

  testWidgets('窄屏 360dp：名称/删除按钮始终可见，布局不溢出', (tester) async {
    recognitionService.outcome = await comboOutcome();
    // 窄屏 360dp（小屏机）：覆盖名称行与克数行的宽度压力。
    await pumpPage(tester, width: 360, height: 800);
    await pickPhotoAndRecognize(tester);

    // 命中条目：库内规范名可见；未命中条目：模型名 + 双标记可见；
    // 每行删除按钮均在且可点（find 即渲染，tap 命中即可点）。
    expect(inSheet(find.text('白米饭')), findsOneWidget);
    expect(inSheet(find.text('鸡蛋')), findsOneWidget);
    expect(inSheet(find.text('薯片')), findsOneWidget);
    expect(inSheet(find.text('库未收录，将自动新建')), findsOneWidget);
    expect(inSheet(find.text('请确认')), findsOneWidget);
    expect(inSheet(find.byIcon(Icons.close)), findsNWidgets(3));
    // 溢出断言：明细行内容不得超出行容器右边界。
    final sheetRight = tester.getTopRight(find.byType(BottomSheet)).dx;
    for (final w in tester.widgetList<Text>(inSheet(find.byType(Text)))) {
      if (w.data == null || w.data!.isEmpty) continue;
      final right = tester.getTopRight(find.byWidget(w)).dx;
      expect(
        right,
        lessThanOrEqualTo(sheetRight + 0.5),
        reason: '文本「${w.data}」右缘 $right 超出弹层右缘 $sheetRight',
      );
    }
    await settleUi(tester);
  });

  testWidgets('窄屏 + 大字体（360dp × 1.3 文本缩放）：名称仍可见不溢出', (tester) async {
    recognitionService.outcome = await comboOutcome();
    // 真机高发场景：系统大字体 + 窄屏（截图反馈名称不可见的复现口径）。
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPage(tester, width: 360, height: 800);
    await pickPhotoAndRecognize(tester);

    expect(inSheet(find.text('白米饭')), findsOneWidget);
    expect(inSheet(find.text('鸡蛋')), findsOneWidget);
    expect(inSheet(find.text('薯片')), findsOneWidget);
    expect(inSheet(find.byIcon(Icons.close)), findsNWidgets(3));
    // 溢出断言：行内所有文本右缘不得超出弹层右缘。
    final sheetRight = tester.getTopRight(find.byType(BottomSheet)).dx;
    for (final w in tester.widgetList<Text>(inSheet(find.byType(Text)))) {
      if (w.data == null || w.data!.isEmpty) continue;
      final right = tester.getTopRight(find.byWidget(w)).dx;
      expect(
        right,
        lessThanOrEqualTo(sheetRight + 0.5),
        reason: '文本「${w.data}」右缘 $right 超出弹层右缘 $sheetRight',
      );
    }
    await settleUi(tester);
  });

  testWidgets('全部删除后「全部记录」禁用，不入账', (tester) async {
    recognitionService.outcome = await comboOutcome();
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    // 删光三条。
    for (var i = 0; i < 3; i++) {
      await tester.tap(inSheet(find.byIcon(Icons.close)).first);
      await tester.pump();
    }
    expect(inSheet(find.text('白米饭')), findsNothing);

    final logAll = tester.widget<FilledButton>(
      inSheet(find.widgetWithText(FilledButton, '全部记录')),
    );
    expect(logAll.onPressed, isNull); // 禁用
    await settleUi(tester);
  });
}

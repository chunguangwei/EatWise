import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_label_ocr_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../recognition/recognition_test_fakes.dart';
import '../record_test_helper.dart';

/// 「拍营养表」（自定义食物弹层）widget 测试：入口显隐（端侧可用性）、
/// OCR 预填四营养 + 「AI 读表，请核对」徽标、读不出降级手动填写。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakeCustomFoodRemote customRemote;
  late FakePhotoPickerGateway photoGateway;
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
    customRemote = FakeCustomFoodRemote();
    photoGateway = FakePhotoPickerGateway();
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

  OnDeviceNutritionLabelOcrService ocrService() {
    return OnDeviceNutritionLabelOcrService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
      normalizeImage: (bytes) async => bytes,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool ocrAvailable,
  }) async {
    // 放大测试屏幕：弹层内容高，默认尺寸按钮不可点。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          customFoodRemoteProvider.overrideWithValue(customRemote),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          if (ocrAvailable)
            nutritionLabelOcrServiceProvider.overrideWithValue(ocrService()),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 打开自定义食物弹层（搜索无结果 → CTA）。
  Future<void> openSheet(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('找不到？添加自定义食物'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加自定义食物'), findsOneWidget);
  }

  /// 拍营养表：按钮 → 来源面板 → 拍照（fake 取图）。
  Future<void> tapOcrAndPick(WidgetTester tester) async {
    await tester.tap(find.text('拍营养表'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  /// 弹层字段（0 菜名 / 1 别名 / 2 热量 / 3 蛋白 / 4 碳水 / 5 脂肪）。
  String fieldText(WidgetTester tester, int index) {
    return tester
        .widget<TextFormField>(find.byType(TextFormField).at(index))
        .controller!
        .text;
  }

  testWidgets('端侧不可用 → 不渲染「拍营养表」入口（不误导）', (tester) async {
    await pumpPage(tester, ocrAvailable: false);
    await openSheet(tester);

    expect(find.text('拍营养表'), findsNothing);
    expect(find.text('AI 估算'), findsOneWidget); // 原有入口不受影响
    await settleUi(tester);
  });

  testWidgets('拍营养表读数成功：kJ 换算预填四营养 + 「AI 读表，请核对」徽标', (tester) async {
    gateway.imageResponse = '1540 kJ => 7.2 => 53.0 => 32.1';
    await pumpPage(tester, ocrAvailable: true);
    await openSheet(tester);

    await tapOcrAndPick(tester);

    // 1540 kJ / 4.184 ≈ 368.1 kcal（解析层换算，不信模型口算）。
    expect(fieldText(tester, 2), '368.1');
    expect(fieldText(tester, 3), '7.2');
    expect(fieldText(tester, 4), '53');
    expect(fieldText(tester, 5), '32.1');
    expect(find.text('AI 读表，请核对'), findsOneWidget);

    // 用户改值 → 徽标清除（徽标只覆盖未改动的读数）。
    await tester.enterText(find.byType(TextFormField).at(2), '370');
    await tester.pump();
    expect(find.text('AI 读表，请核对'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('读不出 → 降级提示手动填写，表单不动不阻断', (tester) async {
    gateway.imageResponse = '无法识别';
    await pumpPage(tester, ocrAvailable: true);
    await openSheet(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '手工饼干');

    await tapOcrAndPick(tester);

    expect(find.text('没读出来，换个角度拍或手动填写'), findsOneWidget);
    expect(find.text('添加自定义食物'), findsOneWidget); // 弹层仍在
    expect(fieldText(tester, 0), '手工饼干'); // 已输入内容不丢
    expect(fieldText(tester, 2), isEmpty); // 不写入错误值
    await settleUi(tester);
  });
}

/// 推理网关 Fake（本文件只走视觉推理）。
final class _FakeGateway implements OnDeviceLlmGateway {
  bool loaded = false;
  bool vision = false;
  String imageResponse = '';
  int inferImageCalls = 0;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  bool get audioEnabled => false; // 本用例不走音频

  @override
  Future<void> load(
    String modelPath, {
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
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
    double? topP,
    int seed = 42,
  }) {
    throw UnimplementedError('本测试只走视觉推理');
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
  }) {
    throw UnimplementedError('本测试不走音频推理');
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
  }) async {
    inferImageCalls++;
    return imageResponse;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}

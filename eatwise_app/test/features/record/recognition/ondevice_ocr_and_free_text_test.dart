import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_free_text_meal_service.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_label_ocr_service.dart';
import 'package:eatwise/features/record/recognition/domain/free_text_meal_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 营养表 OCR 服务 + 自由记文本服务单测（网关 Fake，不触碰真实引擎）。
void main() {
  final photoBytes = Uint8List.fromList(<int>[1, 2, 3]);

  Food food({required String id, required String zh, String en = ''}) => Food(
    id: id,
    nameZh: zh,
    nameEn: en,
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 25.9,
    fatPer100g: 0.3,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: 'req-$id',
  );

  OnDeviceNutritionLabelOcrService makeOcr(_FakeGateway gateway) {
    return OnDeviceNutritionLabelOcrService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
      normalizeImage: (bytes) async => bytes,
    );
  }

  OnDeviceFreeTextMealService makeFreeText(
    _FakeGateway gateway, {
    Map<String, List<Food>> searchResults = const <String, List<Food>>{},
  }) {
    return OnDeviceFreeTextMealService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
      searchFoods: (query) async => searchResults[query] ?? <Food>[],
    );
  }

  group('OnDeviceNutritionLabelOcrService', () {
    test('读表成功：kJ 换算 + 正常值不存疑', () async {
      final gateway = _FakeGateway()
        ..imageResponse = '1540 kJ => 7.2 => 53.0 => 32.1';
      final service = makeOcr(gateway);

      final reading = await service.read(photoBytes);

      expect(reading, isNotNull);
      expect(reading!.values.kcal, closeTo(368.1, 0.1));
      expect(reading.dubious, isFalse);
    });

    test('读表成功但合理性命中 → dubious 标「请核对」', () async {
      final gateway = _FakeGateway()
        ..imageResponse = '6200 kJ => 10 => 10 => 10'; // ≈1481 kcal 超限
      final service = makeOcr(gateway);

      final reading = await service.read(photoBytes);

      expect(reading, isNotNull);
      expect(reading!.dubious, isTrue);
    });

    test('读不出（无法识别/乱码）→ null（UI 降级手动填写）', () async {
      final gateway = _FakeGateway()..imageResponse = '无法识别';
      final service = makeOcr(gateway);

      expect(await service.read(photoBytes), isNull);
    });

    test('以视觉能力加载（与拍照识别共用热引擎）', () async {
      final gateway = _FakeGateway()
        ..imageResponse = '1540 kJ => 7.2 => 53.0 => 32.1';
      final service = makeOcr(gateway);

      await service.read(photoBytes);

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('图片解码失败 → null（不触发推理）', () async {
      final gateway = _FakeGateway();
      final service = OnDeviceNutritionLabelOcrService(
        gateway: gateway,
        modelPath: () async => '/fake/m.litertlm',
        normalizeImage: (_) async => throw StateError('decode failed'),
      );

      expect(await service.read(photoBytes), isNull);
      expect(gateway.inferImageCalls, 0);
    });

    test('OOM → null 且永久禁用（后续调用短路）', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final service = makeOcr(gateway);

      expect(await service.read(photoBytes), isNull);
      expect(service.isPermanentlyDisabled, isTrue);
      expect(await service.read(photoBytes), isNull);
      expect(gateway.loadCalls, 1);
    });
  });

  group('OnDeviceFreeTextMealService（一句话自由记）', () {
    test('文本明细推理：两行拆分 + 逐条库匹配（命中用库内每100g）', () async {
      final gateway = _FakeGateway()
        ..textResponse =
            '牛肉面 => beef noodle soup => 400 => 110 => 8 => 13 => 4\n'
            '鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8';
      final service = makeFreeText(
        gateway,
        searchResults: <String, List<Food>>{
          '鸡蛋': [food(id: 'f-egg', zh: '鸡蛋', en: 'Egg')],
          // 牛肉面库未命中：保留模型估值
        },
      );

      final items = await service.parse('中午吃了一碗牛肉面加个蛋');

      expect(items, isNotNull);
      expect(items, hasLength(2));
      expect(items![0].name, '牛肉面');
      expect(items[0].isMatched, isFalse);
      expect(items[0].grams, 400);
      expect(items[0].confidence, 0.4); // 未命中低置信
      expect(items[1].food!.id, 'f-egg');
      expect(items[1].grams, 50);
      expect(items[1].confidence, 0.85);
      // 文本路径走 infer（非 inferWithImage），prompt 含原文。
      expect(gateway.inferTextCalls, 1);
      expect(gateway.inferImageCalls, 0);
      expect(gateway.lastPrompt, contains('中午吃了一碗牛肉面加个蛋'));
      expect(gateway.lastSystemInstruction, kFreeTextMealSystemPrompt);
    });

    test('「无法识别」/解析空 → null（UI 回落词典解析）', () async {
      final gateway = _FakeGateway()..textResponse = '无法识别';
      final service = makeFreeText(gateway);

      expect(await service.parse('今天天气不错'), isNull);
    });

    test('引擎错误/模型未下载 → null（静默回落）', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceModelMissingException('模型文件不存在');
      final service = makeFreeText(gateway);

      expect(await service.parse('一碗米饭'), isNull);
    });

    test('空文本 → null（不触碰引擎）', () async {
      final gateway = _FakeGateway();
      final service = makeFreeText(gateway);

      expect(await service.parse('   '), isNull);
      expect(gateway.loadCalls, 0);
    });

    test('OOM → null 且永久禁用', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final service = makeFreeText(gateway);

      expect(await service.parse('一碗米饭'), isNull);
      expect(service.isPermanentlyDisabled, isTrue);
      expect(await service.parse('一碗米饭'), isNull);
      expect(gateway.loadCalls, 1);
    });

    test('统一以视觉能力加载（避免与拍照识别来回重建引擎）', () async {
      final gateway = _FakeGateway()
        ..textResponse = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
      final service = makeFreeText(gateway);

      await service.parse('一碗米饭');

      expect(gateway.lastEnableVision, isTrue);
    });
  });

  group('free_text_meal_logic prompt', () {
    test('错字容错声明 + 七段格式 + 组合描述两行示例', () {
      expect(kFreeTextMealSystemPrompt, contains('错字'));
      expect(kFreeTextMealSystemPrompt, contains('同音字'));
      expect(kFreeTextMealSystemPrompt, contains('无法识别'));
      expect(
        kFreeTextMealSystemPrompt,
        contains('牛肉面 => beef noodle soup => 400 => 110 => 8 => 13 => 4'),
      );
      expect(
        kFreeTextMealSystemPrompt,
        contains('鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8'),
      );
    });

    test('user prompt 带描述并以明细引导结尾', () {
      final prompt = buildFreeTextMealPrompt('一杯拿铁');
      expect(prompt, contains('一杯拿铁'));
      expect(prompt.trimRight(), endsWith('明细：'));
    });
  });
}

/// 推理网关 Fake（文本/视觉双路记录）。
final class _FakeGateway implements OnDeviceLlmGateway {
  bool loaded = false;
  bool vision = false;

  String textResponse = '';
  String imageResponse = '';
  Object? loadError;
  Object? inferError;
  int loadCalls = 0;
  int inferTextCalls = 0;
  int inferImageCalls = 0;
  bool? lastEnableVision;
  String? lastPrompt;
  String? lastSystemInstruction;

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
    loadCalls++;
    lastEnableVision = enableVision;
    final error = loadError;
    if (error != null) throw error;
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
    inferTextCalls++;
    lastPrompt = prompt;
    lastSystemInstruction = systemInstruction;
    final error = inferError;
    if (error != null) throw error;
    return textResponse;
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
    int seed = 42,
  }) async {
    inferImageCalls++;
    lastPrompt = prompt;
    lastSystemInstruction = systemInstruction;
    final error = inferError;
    if (error != null) throw error;
    return imageResponse;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}

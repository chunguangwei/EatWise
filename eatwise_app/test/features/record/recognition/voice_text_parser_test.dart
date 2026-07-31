import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/voice/voice_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 语音轻量解析器单测（D-16：词典匹配 + 份量正则；纯 Dart）。
///
/// 覆盖：中文/英文/混合语句、重量单位（克/g/kg/毫升）、份量词各形态
/// （碗/个/半杯/half a bowl/two slices）、别名命中、英文词边界、
/// 无匹配回退、无份量默认 100g。
void main() {
  const parser = VoiceTextParser();

  const rice = Food(
    id: 'f-rice',
    nameZh: '白米饭',
    nameEn: 'White Rice',
    aliasesZh: '["米饭","白饭"]',
    aliasesEn: '["rice","steamed rice"]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 25.9,
    fatPer100g: 0.3,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: '',
  );
  const egg = Food(
    id: 'f-egg',
    nameZh: '鸡蛋',
    nameEn: 'Egg',
    aliasesZh: '["水煮蛋"]',
    aliasesEn: '["boiled egg"]',
    kcalPer100g: 144,
    proteinPer100g: 13.3,
    carbPer100g: 2.8,
    fatPer100g: 8.8,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: '',
  );
  const milk = Food(
    id: 'f-milk',
    nameZh: '牛奶',
    nameEn: 'Milk',
    aliasesZh: '["纯牛奶"]',
    aliasesEn: '["whole milk"]',
    kcalPer100g: 54,
    proteinPer100g: 3,
    carbPer100g: 3.4,
    fatPer100g: 3.2,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: '',
  );
  final foods = <Food>[rice, egg, milk];

  group('重量单位（数字 + 单位直接给克）', () {
    test('中文「200克」', () {
      final result = parser.parse('米饭200克', foods);
      expect(result.items, hasLength(1));
      expect(result.items.first.food.id, 'f-rice');
      expect(result.items.first.amountG, 200);
    });

    test('英文「200g rice」', () {
      final result = parser.parse('200g rice', foods);
      expect(result.items.single.food.id, 'f-rice');
      expect(result.items.single.amountG, 200);
    });

    test('千克换算「1kg 牛奶」→ 1000g', () {
      final result = parser.parse('1kg 牛奶', foods);
      expect(result.items.single.amountG, 1000);
    });

    test('毫升按 1:1 近似「250毫升牛奶」→ 250g', () {
      final result = parser.parse('250毫升牛奶', foods);
      expect(result.items.single.amountG, 250);
    });
  });

  group('份量词映射（数量词 × 单位克数）', () {
    test('「一碗米饭」→ 200g', () {
      final result = parser.parse('一碗米饭', foods);
      expect(result.items.single.food.id, 'f-rice');
      expect(result.items.single.amountG, 200);
    });

    test('「两个鸡蛋」→ 2 × 100 = 200g', () {
      final result = parser.parse('两个鸡蛋', foods);
      expect(result.items.single.food.id, 'f-egg');
      expect(result.items.single.amountG, 200);
    });

    test('「半杯牛奶」→ 0.5 × 250 = 125g', () {
      final result = parser.parse('半杯牛奶', foods);
      expect(result.items.single.amountG, 125);
    });

    test('「half a bowl of rice」→ 100g', () {
      final result = parser.parse('half a bowl of rice', foods);
      expect(result.items.single.food.id, 'f-rice');
      expect(result.items.single.amountG, 100);
    });

    test('「a glass of milk」→ 250g', () {
      final result = parser.parse('a glass of milk', foods);
      expect(result.items.single.food.id, 'f-milk');
      expect(result.items.single.amountG, 250);
    });
  });

  group('混合语句与多食物', () {
    test('「两个鸡蛋一碗米饭」按语序各算各的份量', () {
      final result = parser.parse('两个鸡蛋一碗米饭', foods);
      expect(result.items, hasLength(2));
      expect(result.items[0].food.id, 'f-egg');
      expect(result.items[0].amountG, 200);
      expect(result.items[1].food.id, 'f-rice');
      expect(result.items[1].amountG, 200);
    });

    test('中英混说「一个鸡蛋和 a glass of milk」', () {
      final result = parser.parse('一个鸡蛋和 a glass of milk', foods);
      expect(result.items, hasLength(2));
      expect(result.items[0].food.id, 'f-egg');
      expect(result.items[0].amountG, 100);
      expect(result.items[1].food.id, 'f-milk');
      expect(result.items[1].amountG, 250);
    });
  });

  group('词典匹配边界', () {
    test('中文别名命中「水煮蛋一个」', () {
      final result = parser.parse('水煮蛋一个', foods);
      expect(result.items.single.food.id, 'f-egg');
      expect(result.items.single.amountG, 100);
    });

    test('英文词边界：price 不命中 rice', () {
      expect(parser.parse('price is nice', foods).isEmpty, isTrue);
    });

    test('无匹配 → 空结果（UI 回退手动搜索提示）', () {
      expect(parser.parse('今天天气不错', foods).isEmpty, isTrue);
    });

    test('未提及份量 → 默认 100g', () {
      final result = parser.parse('米饭', foods);
      expect(result.items.single.amountG, VoiceTextParser.defaultAmountG);
    });

    test('空文本/空词表 → 空结果', () {
      expect(parser.parse('', foods).isEmpty, isTrue);
      expect(parser.parse('米饭', const <Food>[]).isEmpty, isTrue);
    });
  });
}

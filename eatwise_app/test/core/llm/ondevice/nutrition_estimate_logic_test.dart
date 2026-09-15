import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildNutritionPrompt（spike v5 模板）', () {
    test('user 模板逐字：食物：{food}\\n每100克营养：', () {
      expect(buildNutritionPrompt('红烧肉'), '食物：红烧肉\n每100克营养：');
    });

    test('食物名去首尾空白', () {
      expect(buildNutritionPrompt('  米饭  '), '食物：米饭\n每100克营养：');
    });

    test('system prompt 关键规则锚点齐备（v5 定稿）', () {
      const p = kOnDeviceNutritionSystemPrompt;
      expect(p, contains('按通常食用状态估算')); // 食用状态说明（v2 引入）
      expect(p, contains('务必折算到100克')); // 强制 100g 折算
      expect(p, contains('蔬菜20-50千卡')); // 区间锚点（v4 引入）
      expect(p, contains('碳水化合物通常不超过25克/100克')); // 通用规律（v5 引入）
      expect(p, contains('热量 => 蛋白质 => 碳水 => 脂肪')); // 输出协议
    });
  });

  group('parseNutritionOutput（spike 宽松正则）', () {
    test('正常行', () {
      final v = parseNutritionOutput('130 => 2.7 => 30.5 => 0.3');
      expect(v, isNotNull);
      expect(v!.kcal, 130);
      expect(v.proteinG, 2.7);
      expect(v.carbsG, 30.5);
      expect(v.fatG, 0.3);
    });

    test('带前后杂质（全文本取第一组匹配）', () {
      final v = parseNutritionOutput('好的，估算结果：250 => 20 => 25 => 20，仅供参考');
      expect(v, isNotNull);
      expect(v!.kcal, 250);
      expect(v.fatG, 20);
    });

    test('容忍尾部多余 =>（spike 豆腐案例：100 => 7 => 3 => 1 =>）', () {
      final v = parseNutritionOutput('100 => 7 => 3 => 1 =>');
      expect(v, isNotNull);
      expect(v!.kcal, 100);
      expect(v.fatG, 1);
    });

    test('紧凑无空格也可解析', () {
      final v = parseNutritionOutput('35=>0=>8=>0');
      expect(v, isNotNull);
      expect(v!.carbsG, 8);
    });

    test('只有三个数字 → null', () {
      expect(parseNutritionOutput('100 => 7 => 3'), isNull);
    });

    test('无数字文本 → null', () {
      expect(parseNutritionOutput('抱歉，我无法估算这种食物。'), isNull);
      expect(parseNutritionOutput(''), isNull);
    });
  });

  group('isNutritionEstimateDubious（sanity-clamp）', () {
    test('香蕉顽固错误案例：320kcal/79g 碳水 → dubious（宏量 >60g 兜底）', () {
      // spike 实测：香蕉输出宏量折算热量 ≈328 与声称 320 偏差很小，
      // 单靠热量偏差规则拦不住，必须靠碳水 >60g/100g 这条。
      const v = OnDeviceNutritionValues(
        kcal: 320,
        proteinG: 2.3,
        carbsG: 79,
        fatG: 0.3,
      );
      expect(isNutritionEstimateDubious(v), isTrue);
    });

    test('4/4/9 折算热量与声称热量偏差 >50% → dubious', () {
      // 宏量折算 25*4+25*4+25*9=425，声称 100 → 偏差 325%
      const v = OnDeviceNutritionValues(
        kcal: 100,
        proteinG: 25,
        carbsG: 25,
        fatG: 25,
      );
      expect(isNutritionEstimateDubious(v), isTrue);
    });

    test('脂肪 >60g/100g → dubious', () {
      const v = OnDeviceNutritionValues(
        kcal: 700,
        proteinG: 5,
        carbsG: 5,
        fatG: 75,
      );
      expect(isNutritionEstimateDubious(v), isTrue);
    });

    test('合理估算（熟米饭）→ 不 dubious', () {
      const v = OnDeviceNutritionValues(
        kcal: 116,
        proteinG: 2.6,
        carbsG: 25.9,
        fatG: 0.3,
      );
      expect(isNutritionEstimateDubious(v), isFalse);
    });

    test('合理估算（可乐：脂肪蛋白为 0）→ 不 dubious', () {
      const v = OnDeviceNutritionValues(
        kcal: 43,
        proteinG: 0,
        carbsG: 10.6,
        fatG: 0,
      );
      expect(isNutritionEstimateDubious(v), isFalse);
    });

    test('声称热量为 0 但宏量非 0 → dubious（除零保护）', () {
      const v = OnDeviceNutritionValues(
        kcal: 0,
        proteinG: 10,
        carbsG: 10,
        fatG: 0,
      );
      expect(isNutritionEstimateDubious(v), isTrue);
    });
  });
}

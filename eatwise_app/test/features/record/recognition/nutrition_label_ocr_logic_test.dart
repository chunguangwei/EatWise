import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 营养表 OCR 纯函数层单测：kJ→kcal 换算、单位变体、表格式样杂质、
/// 读不出降级、合理性校验。
void main() {
  group('parseNutritionLabelOutput', () {
    test('kJ 单位换算 kcal（1540 kJ ≈ 368.1 kcal）', () {
      final values = parseNutritionLabelOutput(
        '1540 kJ => 7.2 => 53.0 => 32.1',
      );
      expect(values, isNotNull);
      expect(values!.kcal, closeTo(368.1, 0.1));
      expect(values.proteinG, 7.2);
      expect(values.carbsG, 53.0);
      expect(values.fatG, 32.1);
    });

    test('中文单位「千焦」同样换算', () {
      final values = parseNutritionLabelOutput('2016千焦 => 8.0 => 0 => 89');
      expect(values, isNotNull);
      expect(values!.kcal, closeTo(481.8, 0.1)); // 2016 kJ / 4.184
      expect(values.carbsG, 0);
    });

    test('kcal/千卡单位照用不换算', () {
      final values = parseNutritionLabelOutput('368 kcal => 7.2 => 53 => 32.1');
      expect(values!.kcal, 368);
      final zh = parseNutritionLabelOutput('368 千卡 => 7.2 => 53 => 32.1');
      expect(zh!.kcal, 368);
    });

    test('缺单位照用（按 kcal 口径）', () {
      final values = parseNutritionLabelOutput('368 => 7.2 => 53 => 32.1');
      expect(values!.kcal, 368);
    });

    test('容忍前后杂质文本（表头复述/说明行）', () {
      final values = parseNutritionLabelOutput(
        '营养成分表读数如下：\n1540 kJ => 7.2 => 53.0 => 32.1\n以上。',
      );
      expect(values, isNotNull);
      expect(values!.kcal, closeTo(368.1, 0.1));
    });

    test('「无法识别」/数字缺失 → null', () {
      expect(parseNutritionLabelOutput('无法识别'), isNull);
      expect(parseNutritionLabelOutput('看不清'), isNull);
      expect(parseNutritionLabelOutput('1540 kJ => 7.2 => 53'), isNull);
      expect(parseNutritionLabelOutput('abc kJ => 7.2 => 53 => 32'), isNull);
    });
  });

  group('isNutritionLabelReadingDubious', () {
    test('正常读数 → 不存疑', () {
      expect(
        isNutritionLabelReadingDubious(
          const OnDeviceNutritionValues(
            kcal: 368,
            proteinG: 7.2,
            carbsG: 53,
            fatG: 32.1,
          ),
        ),
        isFalse,
      );
    });

    test('热量超物理上限（>900 kcal/100g）→ 存疑', () {
      expect(
        isNutritionLabelReadingDubious(
          const OnDeviceNutritionValues(
            kcal: 1500,
            proteinG: 10,
            carbsG: 10,
            fatG: 10,
          ),
        ),
        isTrue,
      );
    });

    test('宏量超限/折算偏差（复用 sanity-clamp）→ 存疑', () {
      // 蛋白质 70g/100g 触发规则 1。
      expect(
        isNutritionLabelReadingDubious(
          const OnDeviceNutritionValues(
            kcal: 300,
            proteinG: 70,
            carbsG: 5,
            fatG: 10,
          ),
        ),
        isTrue,
      );
      // 折算偏差 >50% 触发规则 2。
      expect(
        isNutritionLabelReadingDubious(
          const OnDeviceNutritionValues(
            kcal: 100,
            proteinG: 10,
            carbsG: 50,
            fatG: 10,
          ),
        ),
        isTrue,
      );
    });

    test('热量为 0 → 存疑（读错标志）', () {
      expect(
        isNutritionLabelReadingDubious(
          const OnDeviceNutritionValues(
            kcal: 0,
            proteinG: 5,
            carbsG: 10,
            fatG: 2,
          ),
        ),
        isTrue,
      );
    });
  });

  group('prompt 模板', () {
    test('system instruction 含读表格式、单位照抄与无法识别出口', () {
      expect(kNutritionLabelOcrSystemPrompt, contains('每100克'));
      expect(kNutritionLabelOcrSystemPrompt, contains('照抄表中印刷的数值和单位'));
      expect(kNutritionLabelOcrSystemPrompt, contains('无法识别'));
      expect(
        kNutritionLabelOcrSystemPrompt,
        contains('1540 kJ => 7.2 => 53.0 => 32.1'),
      );
    });

    test('user prompt 点题并以结果引导结尾', () {
      final prompt = buildNutritionLabelPrompt();
      expect(prompt, contains('营养成分表'));
      expect(prompt.trimRight(), endsWith('结果：'));
    });
  });
}

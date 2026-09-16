import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拍照识别纯函数层单测：prompt 模板、宽松解析、食物库匹配、置信度策略。
void main() {
  Food food({required String id, required String zh, String en = ''}) => Food(
    id: id,
    nameZh: zh,
    nameEn: en,
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 23,
    fatPer100g: 0.3,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: 'req-$id',
  );

  group('prompt 模板', () {
    test('system instruction 含严格行格式与「无法识别」出口', () {
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('食物名 => 热量 => 蛋白质 => 碳水 => 脂肪'),
      );
      expect(kPhotoRecognitionSystemPrompt, contains('无法识别'));
      // v5 营养约束话术保留（视觉版只加识别/命名约束，不改营养口径）。
      expect(kPhotoRecognitionSystemPrompt, contains('熟主食110-150千卡'));
    });

    test('user prompt 点题并以结果引导结尾', () {
      final prompt = buildPhotoRecognitionPrompt();
      expect(prompt, contains('识别'));
      expect(prompt.trimRight(), endsWith('结果：'));
    });
  });

  group('parsePhotoRecognitionOutput', () {
    test('标准行：名 + 四数字', () {
      final parsed = parsePhotoRecognitionOutput(
        '米饭 => 116 => 2.6 => 23 => 0.3',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '米饭');
      expect(
        parsed.values,
        const OnDeviceNutritionValues(
          kcal: 116,
          proteinG: 2.6,
          carbsG: 23,
          fatG: 0.3,
        ),
      );
    });

    test('容忍前后杂质文本，取第一组有效行', () {
      final parsed = parsePhotoRecognitionOutput(
        '好的，识别结果如下：\n番茄炒蛋 => 120 => 6 => 8 => 7\n以上仅供参考。',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '番茄炒蛋');
      expect(parsed.values.kcal, 120);
    });

    test('剥掉模型复述的前缀（食物：/结果：）', () {
      final parsed = parsePhotoRecognitionOutput(
        '食物：米饭 => 116 => 2.6 => 23 => 0.3',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '米饭');
    });

    test('容忍尾部多余 =>（v5 宽松策略平移）', () {
      final parsed = parsePhotoRecognitionOutput('豆腐 => 100 => 7 => 3 => 1 =>');
      expect(parsed, isNotNull);
      expect(parsed!.name, '豆腐');
    });

    test('「无法识别」→ null（走降级）', () {
      expect(parsePhotoRecognitionOutput('无法识别'), isNull);
      expect(parsePhotoRecognitionOutput('照片看不清，无法识别。'), isNull);
    });

    test('纯数字四段（无食物名）→ null（视觉版必须带名）', () {
      expect(parsePhotoRecognitionOutput('116 => 2.6 => 23 => 0.3'), isNull);
    });

    test('数字缺失/非数字 → null', () {
      expect(
        parsePhotoRecognitionOutput('米饭 => 未知 => 2.6 => 23 => 0.3'),
        isNull,
      );
      expect(parsePhotoRecognitionOutput('米饭 => 116 => 2.6 => 23'), isNull);
    });

    test('前缀剥净后名为空 → null', () {
      expect(parsePhotoRecognitionOutput('食物： => 1 => 1 => 1 => 1'), isNull);
    });
  });

  group('matchFoodByName', () {
    final rice = food(id: 'f-rice', zh: '米饭', en: 'Rice');
    final riceNoodle = food(id: 'f-rice-noodle', zh: '米粉', en: 'Rice noodles');

    test('中文名精确命中优先于搜索顺序', () async {
      final match = await matchFoodByName(
        (_) async => [riceNoodle, rice],
        '米饭',
      );
      expect(match, isNotNull);
      expect(match!.food.id, 'f-rice');
      expect(match.exact, isTrue);
    });

    test('英文名精确命中（忽略大小写）', () async {
      final match = await matchFoodByName((_) async => [rice], 'rice');
      expect(match, isNotNull);
      expect(match!.exact, isTrue);
    });

    test('无精确命中 → 取搜索首条并标模糊', () async {
      final match = await matchFoodByName((_) async => [riceNoodle], '番茄炒蛋');
      expect(match, isNotNull);
      expect(match!.food.id, 'f-rice-noodle');
      expect(match.exact, isFalse);
    });

    test('搜索无结果/空名 → null', () async {
      expect(await matchFoodByName((_) async => <Food>[], '外星食物'), isNull);
      expect(await matchFoodByName((_) async => [rice], '  '), isNull);
    });
  });

  group('cleanRecognitionDetail', () {
    test('换行/制表/连续空白压缩为单个空格并去首尾空白', () {
      expect(
        cleanRecognitionDetail('  无法识别。\n画面里似乎\t是  一张桌子 \n'),
        '无法识别。 画面里似乎 是 一张桌子',
      );
    });

    test('短文本原样返回（无省略号）', () {
      expect(cleanRecognitionDetail('无法识别'), '无法识别');
    });

    test('超长截断到 80 字符并以 … 收尾', () {
      final long = '很长' * 50; // 100 字符
      final cleaned = cleanRecognitionDetail(long);
      expect(cleaned.length, kRecognitionDetailMaxLength + 1);
      expect(cleaned, endsWith('…'));
      expect(cleaned.startsWith('很长'), isTrue);
    });

    test('空白-only 输入 → 空串', () {
      expect(cleanRecognitionDetail('  \n\t '), '');
    });
  });

  group('photoRecognitionConfidence', () {
    test('sanity-clamp 命中 → 0.5（必低于 0.7 阈值标「请确认」）', () {
      expect(
        photoRecognitionConfidence(dubious: true, exactNameMatch: true),
        0.5,
      );
    });

    test('精确命中库 → 0.85（高置信）', () {
      expect(
        photoRecognitionConfidence(dubious: false, exactNameMatch: true),
        0.85,
      );
    });

    test('仅模糊命中 → 0.6（标「请确认」）', () {
      expect(
        photoRecognitionConfidence(dubious: false, exactNameMatch: false),
        0.6,
      );
    });
  });
}

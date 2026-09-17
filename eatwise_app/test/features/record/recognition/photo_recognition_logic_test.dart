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
        contains('中文名 => 英文名 => 热量 => 蛋白质 => 碳水 => 脂肪'),
      );
      expect(kPhotoRecognitionSystemPrompt, contains('无法识别'));
      // v5 营养约束话术保留（视觉版只加识别/命名约束，不改营养口径）。
      expect(kPhotoRecognitionSystemPrompt, contains('熟主食110-150千卡'));
    });

    test('命名约束：要求最具体食物名、禁止类别词、双语输出含 few-shot 示例', () {
      expect(kPhotoRecognitionSystemPrompt, contains('最具体的常见中文食物名'));
      expect(kPhotoRecognitionSystemPrompt, contains('禁止只输出类别词'));
      // 双语输出约束（USDA 库英文为主，英文名匹配提命中率）。
      expect(kPhotoRecognitionSystemPrompt, contains('英文通用名'));
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('中文名 => 英文名 => 热量 => 蛋白质 => 碳水 => 脂肪'),
      );
      // few-shot：示例定死输出格式与命名粒度。
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('米饭 => rice => 116 => 2.6 => 23 => 0.3'),
      );
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('番茄炒蛋 => tomato egg stir-fry => 120 => 6 => 8 => 7'),
      );
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('薯片 => potato chips => 536 => 7 => 53 => 32'),
      );
    });

    test('user prompt 点题并以结果引导结尾', () {
      final prompt = buildPhotoRecognitionPrompt();
      expect(prompt, contains('识别'));
      expect(prompt.trimRight(), endsWith('结果：'));
    });
  });

  group('isGenericCategoryName 类别词黑名单', () {
    test('常见类别词命中（中英、忽略大小写与首尾空白）', () {
      for (final word in <String>[
        '水果',
        '蔬菜',
        '肉类',
        '主食',
        '饮料',
        '零食',
        '菜肴',
        '食物',
        'fruit',
        'Fruit',
        ' vegetable ',
        'MEAT',
        'food',
      ]) {
        expect(isGenericCategoryName(word), isTrue, reason: word);
      }
    });

    test('含类别词的具体食物名不误伤（精确匹配口径）', () {
      for (final word in <String>['水果捞', '水果沙拉', '肉夹馍', '苹果', '米饭', '番茄炒蛋']) {
        expect(isGenericCategoryName(word), isFalse, reason: word);
      }
    });
  });

  group('parsePhotoRecognitionOutput', () {
    test('六段双语主格式：中文名 + 英文名 + 四数字', () {
      final parsed = parsePhotoRecognitionOutput(
        '薯片 => potato chips => 536 => 7 => 53 => 32',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '薯片');
      expect(parsed.nameEn, 'potato chips');
      expect(
        parsed.values,
        const OnDeviceNutritionValues(
          kcal: 536,
          proteinG: 7,
          carbsG: 53,
          fatG: 32,
        ),
      );
    });

    test('六段格式容忍前后杂质', () {
      final parsed = parsePhotoRecognitionOutput(
        '识别结果：\n番茄炒蛋 => tomato egg stir-fry => 120 => 6 => 8 => 7\n供参考。',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '番茄炒蛋');
      expect(parsed.nameEn, 'tomato egg stir-fry');
    });

    test('五段兼容格式（模型不守六段约定时回退）：nameEn 为 null', () {
      final parsed = parsePhotoRecognitionOutput(
        '米饭 => 116 => 2.6 => 23 => 0.3',
      );
      expect(parsed, isNotNull);
      expect(parsed!.name, '米饭');
      expect(parsed.nameEn, isNull);
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

    test('英文段须字母开头：纯数字第二段不误判为六段', () {
      // 五段格式若被六段正则误吃，name 会变成数字段——必须回退五段。
      final parsed = parsePhotoRecognitionOutput('豆腐 => 100 => 7 => 3 => 1');
      expect(parsed, isNotNull);
      expect(parsed!.name, '豆腐');
      expect(parsed.nameEn, isNull);
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

    test('双语：中文未命中 → 英文名回退匹配（USDA 库英文为主）', () async {
      final chips = food(id: 'f-chips', zh: '薯片（油炸）', en: 'potato chips');
      final queries = <String>[];
      final match = await matchFoodByName(
        (q) async {
          queries.add(q);
          // 中文名查不到，英文名才命中。
          return q == 'potato chips' ? [chips] : <Food>[];
        },
        '薯片',
        nameEn: 'potato chips',
      );
      expect(match, isNotNull);
      expect(match!.food.id, 'f-chips');
      expect(match.exact, isTrue);
      expect(queries, <String>['薯片', 'potato chips']);
    });

    test('双语：中文已命中 → 不再查英文名', () async {
      final queries = <String>[];
      final match = await matchFoodByName(
        (q) async {
          queries.add(q);
          return [rice];
        },
        '米饭',
        nameEn: 'rice',
      );
      expect(match, isNotNull);
      expect(match!.food.id, 'f-rice');
      expect(queries, <String>['米饭']);
    });

    test('双语均未命中 → null', () async {
      expect(
        await matchFoodByName(
          (_) async => <Food>[],
          '外星食物',
          nameEn: 'alien food',
        ),
        isNull,
      );
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

    test('类别词命中（识别不够具体）→ 0.5，即便精确命中库也必「请确认」', () {
      expect(
        photoRecognitionConfidence(
          dubious: false,
          exactNameMatch: true,
          tooGeneric: true,
        ),
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

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拍照识别纯函数层单测：多行明细 prompt、逐行解析（七段主格式 +
/// 六/五段兼容）、克数 clamp、类别词黑名单、食物库双语匹配、置信度策略。
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

  group('prompt 模板（多行明细协议）', () {
    test('system instruction 含七段行格式与「无法识别」出口', () {
      expect(
        kPhotoRecognitionSystemPrompt,
        contains(
          '中文名 => 英文名 => 估算克数 => 每100克热量 => 每100克蛋白质 => 每100克碳水 => 每100克脂肪',
        ),
      );
      expect(kPhotoRecognitionSystemPrompt, contains('无法识别'));
      // v5 营养约束话术保留（视觉版只加识别/命名/份量约束，不改营养口径）。
      expect(kPhotoRecognitionSystemPrompt, contains('熟主食110-150千卡'));
    });

    test('份量约束：估算克数按图中实际份量（常识锚点）', () {
      expect(kPhotoRecognitionSystemPrompt, contains('一碗米饭约200克'));
      expect(kPhotoRecognitionSystemPrompt, contains('一包薯片约60克'));
      expect(kPhotoRecognitionSystemPrompt, contains('一盘菜约250克'));
    });

    test('包装食品标签提取约束（营养表照抄 + 净含量 + 品牌品名）', () {
      expect(kPhotoRecognitionSystemPrompt, contains('营养成分表'));
      expect(kPhotoRecognitionSystemPrompt, contains('优先照抄标签'));
      expect(kPhotoRecognitionSystemPrompt, contains('不要自己换算'));
      expect(kPhotoRecognitionSystemPrompt, contains('净含量'));
      expect(kPhotoRecognitionSystemPrompt, contains('品牌加品名'));
      // 包装 few-shot：kJ 单位原样透出（Dart 层换算）。
      expect(
        kPhotoRecognitionSystemPrompt,
        contains(
          '清叶堂洋芋片 => potato chips => 50 => 2141 kJ => 6.1 => 53.0 => 30.7',
        ),
      );
    });

    test('散装食物参照物克数估算引导（不上 AR/LiDAR）', () {
      expect(kPhotoRecognitionSystemPrompt, contains('参照物'));
      expect(kPhotoRecognitionSystemPrompt, contains('碗盘直径约11-13厘米'));
    });

    test('组合餐拆分 + few-shot（含三行明细示例）', () {
      expect(kPhotoRecognitionSystemPrompt, contains('组合餐'));
      expect(kPhotoRecognitionSystemPrompt, contains('每种主要食物输出一行'));
      // few-shot：单食物两条 + 组合餐三行明细。
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3'),
      );
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('薯片 => potato chips => 60 => 536 => 7 => 53 => 32'),
      );
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8'),
      );
      expect(
        kPhotoRecognitionSystemPrompt,
        contains('火腿 => ham => 30 => 145 => 16 => 2 => 8'),
      );
    });

    test('命名约束：要求最具体食物名、禁止类别词、英文通用名', () {
      expect(kPhotoRecognitionSystemPrompt, contains('最具体的常见中文食物名'));
      expect(kPhotoRecognitionSystemPrompt, contains('禁止只输出类别词'));
      expect(kPhotoRecognitionSystemPrompt, contains('最常见的通用名'));
    });

    test('user prompt 点题并以结果引导结尾', () {
      final prompt = buildPhotoRecognitionPrompt();
      expect(prompt, contains('识别'));
      expect(prompt.trimRight(), endsWith('结果：'));
    });
  });

  group('parsePhotoRecognitionItems（多行明细解析）', () {
    test('七段主格式单条：中文名 + 英文名 + 克数 + 四营养', () {
      final items = parsePhotoRecognitionItems(
        '薯片 => potato chips => 60 => 536 => 7 => 53 => 32',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '薯片');
      expect(items.single.nameEn, 'potato chips');
      expect(items.single.grams, 60);
      expect(
        items.single.values,
        const OnDeviceNutritionValues(
          kcal: 536,
          proteinG: 7,
          carbsG: 53,
          fatG: 32,
        ),
      );
    });

    test('组合餐三行明细：逐行解析、克数各自独立', () {
      final items = parsePhotoRecognitionItems(
        '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3\n'
        '鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8\n'
        '火腿 => ham => 30 => 145 => 16 => 2 => 8',
      );
      expect(items, hasLength(3));
      expect(items.map((i) => i.name), <String>['米饭', '鸡蛋', '火腿']);
      expect(items.map((i) => i.grams), <double>[200, 50, 30]);
      expect(items[1].values.kcal, 144);
    });

    test('空行/杂质行忽略；单条损坏不拖垮整体', () {
      final items = parsePhotoRecognitionItems(
        '好的，明细如下：\n'
        '\n'
        '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3\n'
        '这一行是解说没有数字\n'
        '鸡蛋 => egg => 坏了 => 不是数字 => x => y\n'
        '火腿 => ham => 30 => 145 => 16 => 2 => 8\n'
        '以上仅供参考。',
      );
      expect(items, hasLength(2));
      expect(items.map((i) => i.name), <String>['米饭', '火腿']);
    });

    test('六段兼容（无克数）：grams 为 null', () {
      final items = parsePhotoRecognitionItems(
        '番茄炒蛋 => tomato egg stir-fry => 120 => 6 => 8 => 7',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '番茄炒蛋');
      expect(items.single.nameEn, 'tomato egg stir-fry');
      expect(items.single.grams, isNull);
      expect(items.single.values.kcal, 120);
    });

    test('五段兼容（模型不守新格式时回退）：nameEn/grams 均为 null', () {
      final items = parsePhotoRecognitionItems('米饭 => 116 => 2.6 => 23 => 0.3');
      expect(items, hasLength(1));
      expect(items.single.name, '米饭');
      expect(items.single.nameEn, isNull);
      expect(items.single.grams, isNull);
    });

    test('英文段须字母开头：五段不被六段/七段正则误吃', () {
      final items = parsePhotoRecognitionItems('豆腐 => 100 => 7 => 3 => 1');
      expect(items, hasLength(1));
      expect(items.single.name, '豆腐');
      expect(items.single.nameEn, isNull);
    });

    test('剥掉模型复述的前缀（食物：/结果：），容忍尾部多余 =>', () {
      final items = parsePhotoRecognitionItems(
        '食物：米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3 =>',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '米饭');
      expect(items.single.grams, 200);
    });

    test('包装标签行：kJ 单位透出 → Dart 层换算 kcal + fromLabel 标记', () {
      final items = parsePhotoRecognitionItems(
        '清叶堂洋芋片 => potato chips => 50 => 2141 kJ => 6.1 => 53.0 => 30.7',
      );
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.name, '清叶堂洋芋片');
      expect(item.nameEn, 'potato chips');
      expect(item.grams, 50); // 净含量直填
      expect(item.fromLabel, isTrue);
      expect(item.values.kcal, closeTo(511.7, 0.1)); // 2141 / 4.184
      expect(item.values.proteinG, 6.1);
      expect(item.values.carbsG, 53.0);
      expect(item.values.fatG, 30.7);
    });

    test('包装标签行：千卡标注/中文单位 原样或换算正确', () {
      final kcal = parsePhotoRecognitionItems(
        '某饼干 => cookies => 40 => 480 kcal => 6 => 60 => 22',
      );
      expect(kcal.single.fromLabel, isTrue);
      expect(kcal.single.values.kcal, 480);
      final kj = parsePhotoRecognitionItems(
        '某饼干 => cookies => 40 => 2008千焦 => 6 => 60 => 22',
      );
      expect(kj.single.fromLabel, isTrue);
      expect(kj.single.values.kcal, closeTo(479.9, 0.1)); // 2008 / 4.184
    });

    test('散装估算行（无单位）→ fromLabel=false（向后兼容）', () {
      final items = parsePhotoRecognitionItems(
        '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3',
      );
      expect(items.single.fromLabel, isFalse);
      expect(items.single.values.kcal, 116);
    });

    test('「无法识别」→ 空列表（走 parse_failed 降级）', () {
      expect(parsePhotoRecognitionItems('无法识别'), isEmpty);
      expect(parsePhotoRecognitionItems('照片看不清，无法识别。'), isEmpty);
    });

    test('纯数字行/无名字行 → 跳过', () {
      expect(parsePhotoRecognitionItems('116 => 2.6 => 23 => 0.3'), isEmpty);
      expect(
        parsePhotoRecognitionItems('食物： => 116 => 2.6 => 23 => 0.3'),
        isEmpty,
      );
    });
  });

  group('克数 clamp（kPhotoGramsMin/Max = 1–2000）', () {
    test('区间内原样；越界判定可疑', () {
      expect(isPhotoGramsSuspicious(200), isFalse);
      expect(isPhotoGramsSuspicious(1), isFalse);
      expect(isPhotoGramsSuspicious(2000), isFalse);
      expect(isPhotoGramsSuspicious(0.5), isTrue);
      expect(isPhotoGramsSuspicious(3000), isTrue);
    });

    test('clamp 回区间', () {
      expect(clampPhotoGrams(200), 200);
      expect(clampPhotoGrams(0), 1);
      expect(clampPhotoGrams(3000), 2000);
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

  group('matchFoodByName（双语匹配）', () {
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

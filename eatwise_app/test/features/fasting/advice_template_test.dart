import 'dart:convert';
import 'dart:io';

import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 《规格-营养规则》§5.2 单测清单 U23/U24（建议模板库，D-05/D-15）。
///
/// 直接读取 i18n 源文件（i18n/strings_*.i18n.json）校验：
/// - U23：规则引擎可能产出的全部 advice key 存在且中英双语非空；
/// - U24：不含「必须/禁止/RDA」等违禁词（品牌语气，规格 §2.3 禁用清单）。
void main() {
  late Map<String, String> zh;
  late Map<String, String> en;

  setUpAll(() async {
    zh = await _flatten('i18n/strings_zh-CN.i18n.json');
    en = await _flatten('i18n/strings_en.i18n.json');
  });

  test('U23 规则引擎可达的全部 advice key 存在且中英非空（4 营养素 × '
      '可达落区 × zero + 4 餐段）', () {
    // 规则引擎可达落区（§4.2：kcal/carb/fat 五区，protein 四区无黄-高）
    const subZones = <NutrientType, List<SignalSubZone>>{
      NutrientType.kcal: SignalSubZone.values,
      NutrientType.protein: <SignalSubZone>[
        SignalSubZone.green,
        SignalSubZone.yellowLow,
        SignalSubZone.redLow,
        SignalSubZone.redHigh,
        SignalSubZone.redOver,
      ],
      NutrientType.carb: SignalSubZone.values,
      NutrientType.fat: SignalSubZone.values,
    };
    final requiredKeys = <String>{
      for (final entry in subZones.entries)
        for (final sub in entry.value) adviceKeyFor(entry.key, sub),
      for (final nutrient in NutrientType.values)
        adviceKeyFor(nutrient, SignalSubZone.redLow, zeroIntake: true),
      for (final segment in MealSegment.values) mealActionKeyFor(segment),
    };
    for (final key in requiredKeys) {
      expect(zh[key], isNotNull, reason: 'zh 缺 key: $key');
      expect(zh[key], isNotEmpty, reason: 'zh 空翻译: $key');
      expect(en[key], isNotNull, reason: 'en 缺 key: $key');
      expect(en[key], isNotEmpty, reason: 'en 空翻译: $key');
    }
  });

  test('U24 文案扫描：不含「必须/禁止/RDA」等违禁词（品牌语气合规）', () {
    final adviceKeys = zh.keys.where((k) => k.startsWith(kAdviceKeyPrefix));
    final zhForbidden = RegExp('必须|禁止|RDA|您');
    final enForbidden = RegExp(
      'must|forbidden|RDA|miracle',
      caseSensitive: false,
    );
    for (final key in adviceKeys) {
      expect(zh[key], isNot(contains(zhForbidden)), reason: 'zh 违禁词: $key');
      expect(en[key], isNot(contains(enForbidden)), reason: 'en 违禁词: $key');
    }
  });
}

/// 读取并拍平 i18n JSON：`{a: {b: "x"}}` → `{"a.b": "x"}`。
Future<Map<String, String>> _flatten(String path) async {
  final json =
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  final out = <String, String>{};
  void walk(Map<String, dynamic> node, String prefix) {
    for (final entry in node.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        walk(value, key);
      } else if (value is String) {
        out[key] = value;
      }
    }
  }

  walk(json, '');
  return out;
}

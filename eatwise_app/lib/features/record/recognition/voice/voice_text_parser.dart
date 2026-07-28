import 'dart:convert';

import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/voice/voice_portion_map.dart';

/// 语音解析命中项：一个食物 + 解析出的份量（克）。
final class VoiceParsedItem {
  const VoiceParsedItem({
    required this.food,
    required this.amountG,
    required this.matchedTerm,
  });

  /// 命中的食物库条目。
  final Food food;

  /// 解析出的份量（克）；未提及份量时为 [VoiceTextParser.defaultAmountG]。
  final double amountG;

  /// 命中词表中的哪个词（埋点/调试）。
  final String matchedTerm;
}

/// 语音文本解析结果（可能一句话提到多个食物，如「两个鸡蛋一碗米饭」）。
final class VoiceParseResult {
  const VoiceParseResult(this.items);

  /// 按语句出现顺序排列的命中项。
  final List<VoiceParsedItem> items;

  /// 是否一个食物都没认出来（UI 走「换个说法或手动搜索」提示）。
  bool get isEmpty => items.isEmpty;
}

/// 语音录入轻量解析器（D-16：食物库词典匹配 + 份量正则，
/// 不引入独立 NLP 服务；纯 Dart，可全量单测）。
///
/// 规则概览：
/// 1. 词典匹配：把食物库中文名/英文名/中英别名（JSON 数组）建成词表，
///    中文按子串包含、英文按词边界匹配；同食物取最长命中词，
///    多个食物按语句出现顺序输出。
/// 2. 份量解析：优先「数字 + 重量单位」（200克/200g/1kg/250ml）；
///    否则「数量词 + 份量词」（一碗/两个/half a bowl/two slices）经
///    映射表折算克数；单个食物且前缀无份量时回退整句解析；
///    都没有则默认 100g。
final class VoiceTextParser {
  const VoiceTextParser();

  /// 未提及份量时的默认份量（克），与手动选择食物的默认值一致。
  static const double defaultAmountG = 100;

  /// 数字 + 重量单位（克/g/gram/千克/kg/毫升/ml；ml 按水密度近似 1g，
  /// 〔假设〕随份量映射表一并校准）。
  static final RegExp _weightPattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*(千克|公斤|kg|克|grams?|g|毫升|ml)',
  );

  /// 中文「数量词 + 份量词」（一碗/两个/半杯/三片/一拳头）。
  static final RegExp _portionPatternZh = RegExp(
    '([半一二两三四五六七八九十]+|\\d+(?:\\.\\d+)?)\\s*'
    '(拳头|碗|杯|个|只|颗|份|片|勺)',
  );

  /// 英文「数量词 + 份量词」（half a bowl / two slices / a cup of /
  /// glass of milk）；half 前缀按 0.5 折算。
  static final RegExp _portionPatternEn = RegExp(
    '(half\\s+)?'
    '(?:(a|an|one|two|three|four|five|six|seven|eight|nine|ten|'
    '\\d+(?:\\.\\d+)?)\\s+)?'
    '(bowl|cup|glass|piece|serving|portion|slice|spoon|tablespoon|fist)s?',
  );

  /// 解析一段语音识别文本。
  VoiceParseResult parse(String transcript, List<Food> foods) {
    final text = transcript.trim();
    if (text.isEmpty || foods.isEmpty) return const VoiceParseResult([]);
    final matches = _findFoodMatches(text, foods);
    if (matches.isEmpty) return const VoiceParseResult([]);
    final items = <VoiceParsedItem>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      // 份量只从该食物词之前的片段取（上一个食物词之后起算），
      // 避免「两个鸡蛋一碗米饭」把米饭也按「两个」计。
      final segmentStart = i == 0 ? 0 : matches[i - 1].end;
      final segment = text.substring(segmentStart, match.start);
      var amount = _parseAmount(segment);
      if (amount == null && matches.length == 1) {
        // 单食物且前缀没提到份量 → 整句再找一次（「米饭200克」）。
        amount = _parseAmount(text);
      }
      items.add(
        VoiceParsedItem(
          food: match.food,
          amountG: amount ?? defaultAmountG,
          matchedTerm: match.term,
        ),
      );
    }
    return VoiceParseResult(items);
  }

  // ---- 词典匹配 ----

  /// 在文本中找全部食物命中（中文子串包含 / 英文词边界），
  /// 按出现位置升序；同一食物保留最长命中词的最左出现。
  List<_FoodMatch> _findFoodMatches(String text, List<Food> foods) {
    final lower = text.toLowerCase();
    final matches = <_FoodMatch>[];
    for (final food in foods) {
      _FoodMatch? best;
      for (final term in _termsOf(food)) {
        final span = _findTerm(text, lower, term);
        if (span == null) continue;
        final candidate = _FoodMatch(
          food: food,
          term: term,
          start: span.$1,
          end: span.$2,
        );
        if (best == null ||
            term.length > best.term.length ||
            (term.length == best.term.length && span.$1 < best.start)) {
          best = candidate;
        }
      }
      if (best != null) matches.add(best);
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  /// 单个词的定位：含中文按子串包含；纯英文按词边界（防 rice 命中 price）。
  (int, int)? _findTerm(String text, String lower, String term) {
    final isAscii = term.codeUnits.every((c) => c < 128);
    if (!isAscii) {
      final index = text.indexOf(term);
      return index < 0 ? null : (index, index + term.length);
    }
    final pattern = RegExp('(^|[^a-z])${RegExp.escape(term.toLowerCase())}');
    final match = pattern.firstMatch(lower);
    if (match == null) return null;
    final start = match.end - term.length;
    return (start, start + term.length);
  }

  /// 食物词表：中文名 + 英文名 + 中英别名（JSON 数组，与 FoodDao 同构）。
  List<String> _termsOf(Food food) {
    return <String>[
      food.nameZh,
      food.nameEn,
      ..._decodeAliases(food.aliasesZh),
      ..._decodeAliases(food.aliasesEn),
    ].where((t) => t.trim().isNotEmpty).toList();
  }

  List<String> _decodeAliases(String json) {
    try {
      return (jsonDecode(json) as List<dynamic>).cast<String>();
    } on Object {
      return const <String>[];
    }
  }

  // ---- 份量解析 ----

  /// 从片段解析份量（克）：重量单位优先，其次份量词映射。
  double? _parseAmount(String segment) {
    final weight = _weightPattern.firstMatch(segment);
    if (weight != null) {
      final value = double.parse(weight.group(1)!);
      final unit = weight.group(2)!.toLowerCase();
      return switch (unit) {
        '千克' || '公斤' || 'kg' => value * 1000,
        _ => value, // 克/g/gram/毫升/ml 均按 1:1 克
      };
    }
    final zh = _portionPatternZh.firstMatch(segment);
    if (zh != null) {
      final count =
          kChineseNumerals[zh.group(1)!] ?? double.tryParse(zh.group(1)!) ?? 1;
      return count * (kPortionGramsZh[zh.group(2)!] ?? defaultAmountG);
    }
    final en = _portionPatternEn.firstMatch(segment.toLowerCase());
    if (en != null) {
      final half = en.group(1) != null ? 0.5 : 1.0;
      final numeral = en.group(2);
      final count = numeral == null
          ? 1.0
          : (kEnglishNumerals[numeral] ?? double.tryParse(numeral) ?? 1.0);
      return half * count * (kPortionGramsEn[en.group(3)!] ?? defaultAmountG);
    }
    return null;
  }
}

final class _FoodMatch {
  const _FoodMatch({
    required this.food,
    required this.term,
    required this.start,
    required this.end,
  });

  final Food food;
  final String term;
  final int start;
  final int end;
}

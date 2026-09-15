/// 端侧营养估算纯函数层（domain 风格，零 Flutter/插件依赖，可单测）。
///
/// Prompt 与解析正则原样来自端侧推理 spike 报告 §6 的 v5 定稿
/// （temperature=0.15, topK=1, seed=42, maxOutputTokens=96 下 40 次推理
/// 解析成功率 100%）。数值质量定位：食物库未命中时的兜底估算，
/// 量级正确率 ~80%，顽固单品错误（如香蕉碳水 79g）靠 [isNutritionEstimateDubious]
/// 标记「估算存疑」走人工确认，绝不能当精确值直接入库。
library;

/// spike v5 定稿 system instruction（逐字搬运，勿改动措辞——五轮调优结果）。
const String kOnDeviceNutritionSystemPrompt =
    '你是营养成分估算助手。用户给出一个食物名称，你估算其每100克可食部的营养。'
    '按通常食用状态估算：米饭、面条等主食指煮熟后的成品，菜名指烧制完成的成品菜，肉蛋水果按生鲜。'
    '务必折算到100克：即使食物通常按瓶、罐、个出售（如一罐可乐330毫升、一个鸡蛋50克），也只估算100克的量。'
    '常见食物每100克热量参考范围：蔬菜20-50千卡，水果30-90千卡，熟主食110-150千卡，'
    '瘦肉蛋100-200千卡，肥肉菜品250-500千卡，含糖饮料35-50千卡。'
    '一般规律：新鲜水果蔬菜水分高，碳水化合物通常不超过25克/100克（干果除外）；'
    '可乐、果汁等纯饮料的脂肪和蛋白质为0。'
    '只输出一行，格式为四个数字用 => 分隔：热量 => 蛋白质 => 碳水 => 脂肪，'
    '单位分别是千卡、克、克、克。只写数字和 =>，不要任何其他文字。';

/// spike v5 user 模板（`食物：{food}\n每100克营养：`）。
String buildNutritionPrompt(String foodName) {
  return '食物：${foodName.trim()}\n每100克营养：';
}

/// 宽松解析正则（spike 定稿）：全文本取第一组 `a => b => c => d`，
/// 容忍尾部多余 `=>` 与前后杂质（实测「豆腐 100 => 7 => 3 => 1 =>」可解析）。
final RegExp _parseRegex = RegExp(
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 端侧估算出的每 100g 营养值。
final class OnDeviceNutritionValues {
  const OnDeviceNutritionValues({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  @override
  bool operator ==(Object other) =>
      other is OnDeviceNutritionValues &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG);

  @override
  String toString() =>
      'OnDeviceNutritionValues($kcal kcal, P$proteinG, C$carbsG, F$fatG)';
}

/// 解析端侧模型输出原文 → 每 100g 营养值；匹配失败返回 null（上层走重试/降级）。
OnDeviceNutritionValues? parseNutritionOutput(String text) {
  final m = _parseRegex.firstMatch(text);
  if (m == null) return null;
  final values = [
    for (var i = 1; i <= 4; i++) double.tryParse(m.group(i)!) ?? double.nan,
  ];
  if (values.any((v) => !v.isFinite)) return null;
  return OnDeviceNutritionValues(
    kcal: values[0],
    proteinG: values[1],
    carbsG: values[2],
    fatG: values[3],
  );
}

/// sanity-clamp（spike §6 定稿规则）：满足任一条即判定「估算存疑」——
/// 1. 蛋白质/碳水/脂肪任一 > 60g/100g（香蕉型顽固错误靠这条兜底：
///    320kcal/79g 碳水时宏量折算热量与声称热量偏差反而很小，单靠规则 2 拦不住）；
/// 2. 宏量营养素按 4/4/9 kcal/g 折算的热量与声称热量偏差 > 50%。
bool isNutritionEstimateDubious(OnDeviceNutritionValues v) {
  if (v.proteinG > 60 || v.carbsG > 60 || v.fatG > 60) return true;
  final macroKcal = v.proteinG * 4 + v.carbsG * 4 + v.fatG * 9;
  final deviation = (macroKcal - v.kcal).abs() / (v.kcal > 0 ? v.kcal : 1);
  return deviation > 0.5;
}

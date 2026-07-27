import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/domain/signal_light.dart';

/// DailyNutrition 聚合与建议 key 生成（《规格-营养规则》§3.2/§4/§6，D-05）。

/// 餐段（§4.1〔假设〕：05–10 早 / 10–15 午 / 15–21 晚 / 21–05 加餐）。
enum MealSegment { breakfast, lunch, dinner, snack }

/// 当日累计摄入（FoodEntry 营养快照逐项求和后的输入，§6.3）。
final class DailyIntake {
  const DailyIntake({
    required this.entryCount,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
  });

  /// 当日 FoodEntry 条数；0 → 不显示任何信号灯（§3.2，U21）。
  final int entryCount;

  /// 累计热量（kcal）。
  final double kcal;

  /// 累计蛋白质（g）。
  final double proteinG;

  /// 累计碳水（g）。
  final double carbG;

  /// 累计脂肪（g）。
  final double fatG;
}

/// 当日信号灯判定结果。
final class DailySignal {
  const DailySignal({
    required this.hasData,
    required this.verdicts,
    required this.adviceKeys,
    required this.configVersion,
  });

  /// 当日是否有记录；false 时前端不渲染信号灯（§3.2）。
  final bool hasData;

  /// 四营养素落区（hasData=false 时为空）。
  final Map<NutrientType, SignalVerdict> verdicts;

  /// 当日展示的 i18n key 列表（随 zones 生成；零摄入营养素用
  /// `advice.{nutrient}.zero` 专用文案，§4.4 / U22）。
  final List<String> adviceKeys;

  /// 判定所用配置版本号。
  final String configVersion;
}

/// 建议模板 key 前缀（i18n 规格 §2.2：模块.页面.元素[.变体]）。
const String kAdviceKeyPrefix = 'nutrition.signalCard.advice';

/// 落区 → 建议模板 key（§4.2：热量/碳水/脂肪黄区拆低/高，
/// 蛋白质红区拆低/过量；零摄入走 zero 专用文案，§4.4）。
String adviceKeyFor(
  NutrientType nutrient,
  SignalSubZone subZone, {
  bool zeroIntake = false,
}) {
  if (zeroIntake) return '$kAdviceKeyPrefix.${nutrient.name}.zero';
  final zonePart = switch (subZone) {
    SignalSubZone.green => 'green',
    SignalSubZone.yellowLow => 'yellowLow',
    SignalSubZone.yellowHigh => 'yellowHigh',
    SignalSubZone.redLow => 'redLow',
    SignalSubZone.redHigh || SignalSubZone.redOver => 'redHigh',
  };
  return '$kAdviceKeyPrefix.${nutrient.name}.$zonePart';
}

/// 餐段模板 key（§4.3 `{meal_action}` 片段）。
String mealActionKeyFor(MealSegment segment) =>
    '$kAdviceKeyPrefix.meal.${segment.name}';

/// 按本地「距 0:00 分钟数」判定餐段（§4.1〔假设〕）。
MealSegment mealSegmentForMinutes(int minutesOfDay) {
  if (minutesOfDay >= 5 * 60 && minutesOfDay < 10 * 60) {
    return MealSegment.breakfast;
  }
  if (minutesOfDay >= 10 * 60 && minutesOfDay < 15 * 60) {
    return MealSegment.lunch;
  }
  if (minutesOfDay >= 15 * 60 && minutesOfDay < 21 * 60) {
    return MealSegment.dinner;
  }
  return MealSegment.snack;
}

/// 当日信号灯 + 建议 key 生成（§6.1 数据流的纯函数部分）。
///
/// - 当日 0 条记录 → hasData=false，不产出信号灯（§3.2，U21）；
/// - 完成率 p 用未取整原始值判定（§3.1，U20）；
/// - 有记录但某营养素为 0 → 按 p=0 判定 + zero 文案 key（§3.2/§4.4，U22）。
DailySignal evaluateDailySignals(
  DailyIntake intake,
  NutritionGoal goal,
  NutritionRuleConfig config,
) {
  if (intake.entryCount == 0) {
    return DailySignal(
      hasData: false,
      verdicts: const <NutrientType, SignalVerdict>{},
      adviceKeys: const <String>[],
      configVersion: config.version,
    );
  }
  final inputs = <NutrientType, ({double actual, double target})>{
    NutrientType.kcal: (
      actual: intake.kcal,
      target: goal.targetKcal.toDouble(),
    ),
    NutrientType.protein: (
      actual: intake.proteinG,
      target: goal.proteinG.toDouble(),
    ),
    NutrientType.carb: (actual: intake.carbG, target: goal.carbG.toDouble()),
    NutrientType.fat: (actual: intake.fatG, target: goal.fatG.toDouble()),
  };
  final verdicts = <NutrientType, SignalVerdict>{};
  final keys = <String>[];
  for (final entry in inputs.entries) {
    final nutrient = entry.key;
    final actual = entry.value.actual;
    final p = actual / entry.value.target * 100; // 未取整原始值（§3.1）
    final verdict = classifyVerdict(p, nutrient, config);
    verdicts[nutrient] = verdict;
    keys.add(adviceKeyFor(nutrient, verdict.subZone, zeroIntake: actual == 0));
  }
  return DailySignal(
    hasData: true,
    verdicts: verdicts,
    adviceKeys: keys,
    configVersion: config.version,
  );
}

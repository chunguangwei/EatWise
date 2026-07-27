import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:meta/meta.dart';

/// TDEE 计算纯函数（《规格-营养规则》§1，D-04）。
///
/// 纯函数：无 I/O、无时钟依赖、无副作用；同输入必同输出（§1.7）。

/// 计算输入（§1.1；任一字段缺失或越域 → 走 §1.6 兜底）。
final class UserProfileInput {
  const UserProfileInput({
    this.sex,
    this.age,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.goal,
  });

  /// 生理性别（缺失时兜底值按 unknownKcal）。
  final Sex? sex;

  /// 年龄（岁），取值域 [10, 100]，域外视为缺失〔假设〕。
  final int? age;

  /// 身高（cm），取值域 [100, 250]，域外视为缺失〔假设〕。
  final double? heightCm;

  /// 体重（kg），取值域 [25, 300]，域外视为缺失〔假设〕。
  final double? weightKg;

  /// 活动水平。
  final ActivityLevel? activityLevel;

  /// 目标（减脂 / 维持）。
  final NutritionGoalType? goal;

  /// 是否全部必填项齐备且未越域。
  bool get isComplete =>
      sex != null &&
      age != null &&
      age! >= 10 &&
      age! <= 100 &&
      heightCm != null &&
      heightCm! >= 100 &&
      heightCm! <= 250 &&
      weightKg != null &&
      weightKg! >= 25 &&
      weightKg! <= 300 &&
      activityLevel != null &&
      goal != null;
}

/// 计算输出（§1.5）。
final class NutritionGoal {
  const NutritionGoal({
    required this.bmr,
    required this.tdee,
    required this.targetKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.usedFallback,
    required this.configVersion,
  });

  /// BMR 原始值；走兜底时不计算，为 null（§1.6 不展示）。
  final double? bmr;

  /// TDEE 原始值；走兜底时为 null。
  final double? tdee;

  /// 每日热量目标（取整到 [NutritionRuleConfig.roundingStepKcal]）。
  final int targetKcal;

  /// 蛋白质目标（g，取整到 1 g）。
  final int proteinG;

  /// 碳水目标（g）。
  final int carbG;

  /// 脂肪目标（g）。
  final int fatG;

  /// 是否走了 §1.6 兜底（驱动补全引导）。
  final bool usedFallback;

  /// 计算所用配置版本号（埋点与回溯用）。
  final String configVersion;
}

/// 每日营养目标计算（§1，D-04）。
///
/// - BMR：Mifflin-St Jeor，中间结果不取整；
/// - 目标热量：lose × loseDeficit，maintain × 1.0，触发下限保护
///   （女 ≥1200 / 男 ≥1500）后取整到 10 kcal；
/// - 缺基础信息 → 兜底 1800/2200/2000 kcal（§1.6）。
NutritionGoal computeNutritionGoal(
  UserProfileInput input,
  NutritionRuleConfig config,
) {
  if (!input.isComplete) {
    return _fallback(input, config);
  }
  final sex = input.sex!;
  final w = input.weightKg!;
  final h = input.heightCm!;
  final age = input.age!;

  // §1.2 Mifflin-St Jeor
  final bmr = sex == Sex.male
      ? 10 * w + 6.25 * h - 5 * age + 5
      : 10 * w + 6.25 * h - 5 * age - 161;

  // §1.3 活动系数
  final tdee = bmr * config.activityFactors[input.activityLevel!]!;

  // §1.4 目标热量 + 下限保护
  var target = input.goal == NutritionGoalType.lose
      ? tdee * config.loseDeficit
      : tdee;
  final minKcal = sex == Sex.male ? config.minKcalMale : config.minKcalFemale;
  if (target < minKcal) target = minKcal;

  final targetKcal = roundKcalToStep(target, config.roundingStepKcal);
  return NutritionGoal(
    bmr: bmr,
    tdee: tdee,
    targetKcal: targetKcal,
    proteinG: _macroGrams(targetKcal, config.proteinRatio, 4),
    carbG: _macroGrams(targetKcal, config.carbRatio, 4),
    fatG: _macroGrams(targetKcal, config.fatRatio, 9),
    usedFallback: false,
    configVersion: config.version,
  );
}

/// §1.6 兜底：女 1800 / 男 2200 / 性别缺失 2000，按同配比折算克数。
NutritionGoal _fallback(UserProfileInput input, NutritionRuleConfig config) {
  final kcal = switch (input.sex) {
    Sex.female => config.fallbackFemaleKcal,
    Sex.male => config.fallbackMaleKcal,
    null => config.fallbackUnknownKcal,
  };
  final targetKcal = roundKcalToStep(kcal, config.roundingStepKcal);
  return NutritionGoal(
    bmr: null,
    tdee: null,
    targetKcal: targetKcal,
    proteinG: _macroGrams(targetKcal, config.proteinRatio, 4),
    carbG: _macroGrams(targetKcal, config.carbRatio, 4),
    fatG: _macroGrams(targetKcal, config.fatRatio, 9),
    usedFallback: true,
    configVersion: config.version,
  );
}

/// 四舍五入到 step（§1.4 取整规则〔假设〕，如 1211.04 → 1210）。
@visibleForTesting
int roundKcalToStep(double value, int step) => (value / step).round() * step;

/// kcal → g：targetKcal × 占比 ÷ 换算系数，四舍五入到 1 g（§2.1）。
int _macroGrams(int targetKcal, double ratio, int kcalPerGram) =>
    (targetKcal * ratio / kcalPerGram).round();

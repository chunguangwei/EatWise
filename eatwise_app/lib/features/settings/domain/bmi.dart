/// BMI 计算与区间判定纯函数（薄荷走查 P1：身体档案页 BMI 区间条 + 状态徽标）。
///
/// 区间来源：中国成人标准 WS/T 428-2013《成人体重判定》——
/// 偏低 <18.5、标准 18.5–23.9、偏高（超重）24.0–27.9、肥胖 ≥28.0。
/// 与 WHO 口径（25/30）不同，数值改动必须先过营养背书。
library;

/// BMI 区间。
enum BmiZone {
  /// 偏低（<18.5）。
  underweight,

  /// 标准（18.5–23.9）。
  normal,

  /// 偏高/超重（24.0–27.9）。
  overweight,

  /// 肥胖（≥28.0）。
  obese,
}

/// 偏低/标准分界（WS/T 428-2013）。
const double bmiUpperUnderweight = 18.5;

/// 标准/偏高分界（WS/T 428-2013）。
const double bmiUpperNormal = 24;

/// 偏高/肥胖分界（WS/T 428-2013）。
const double bmiUpperOverweight = 28;

/// BMI = 体重 kg ÷ 身高 m²。身高必须为正（调用方先做取值域校验，
/// 见 onboarding/domain/onboarding_profile.dart 的 isValidHeightCm）。
double computeBmi({required double heightCm, required double weightKg}) {
  final heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

/// BMI → 区间（边界归入上侧区间：18.5 属标准、24 属偏高、28 属肥胖）。
BmiZone classifyBmi(double bmi) {
  if (bmi < bmiUpperUnderweight) return BmiZone.underweight;
  if (bmi < bmiUpperNormal) return BmiZone.normal;
  if (bmi < bmiUpperOverweight) return BmiZone.overweight;
  return BmiZone.obese;
}

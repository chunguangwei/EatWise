/// onboarding 档案采集（阶段 A：性别/出生年/身高/体重/活动水平）。
///
/// D-18：身高体重属敏感个人信息——整页可跳过、单项可留空，
/// 空项在营养计算中按缺失走 §1.6 兜底。
library;

import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';

/// 生理性别采集项（比 [Sex] 多「不透露」：不透露 = 公式按缺失兜底）。
enum ProfileSex { male, female, undisclosed }

/// 档案表单取值域（与《规格-营养规则》§1.1 取值域一致）。
abstract final class ProfileFieldLimits {
  /// 出生年下界（采集表单口径，上界为当前年）。
  static const int birthYearMin = 1920;

  /// 身高（cm）取值域。
  static const double heightCmMin = 100;
  static const double heightCmMax = 250;

  /// 体重（kg）取值域。
  static const double weightKgMin = 25;
  static const double weightKgMax = 300;
}

/// 出生年合法性（[ProfileFieldLimits.birthYearMin]–[currentYear]，含边界）。
bool isValidBirthYear(int year, int currentYear) {
  return year >= ProfileFieldLimits.birthYearMin && year <= currentYear;
}

/// 身高合法性（cm，§1.1 取值域）。
bool isValidHeightCm(double cm) {
  return cm >= ProfileFieldLimits.heightCmMin &&
      cm <= ProfileFieldLimits.heightCmMax;
}

/// 体重合法性（kg，§1.1 取值域）。
bool isValidWeightKg(double kg) {
  return kg >= ProfileFieldLimits.weightKgMin &&
      kg <= ProfileFieldLimits.weightKgMax;
}

/// 档案采集结果（全部可空；空项走兜底）。
final class OnboardingProfile {
  const OnboardingProfile({
    this.sex,
    this.birthYear,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
  });

  /// 空档案（等价于「跳过档案页」）。
  static const OnboardingProfile empty = OnboardingProfile();

  final ProfileSex? sex;
  final int? birthYear;
  final double? heightCm;
  final double? weightKg;
  final ActivityLevel? activityLevel;

  /// 是否一项都没填。
  bool get isEmpty =>
      sex == null &&
      birthYear == null &&
      heightCm == null &&
      weightKg == null &&
      activityLevel == null;

  /// 转 TDEE 计算输入（§1.1）：不透露/缺失的性别 → null（兜底 2000 kcal）；
  /// 出生年 → 年龄（currentYear − birthYear，越域由 [UserProfileInput]
  /// 取值域判定按缺失处理）。
  UserProfileInput toProfileInput({
    required NutritionGoalType goal,
    required int currentYear,
  }) {
    return UserProfileInput(
      sex: switch (sex) {
        ProfileSex.male => Sex.male,
        ProfileSex.female => Sex.female,
        _ => null,
      },
      age: birthYear == null ? null : currentYear - birthYear!,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      goal: goal,
    );
  }

  OnboardingProfile copyWith({
    ProfileSex? Function()? sex,
    int? Function()? birthYear,
    double? Function()? heightCm,
    double? Function()? weightKg,
    ActivityLevel? Function()? activityLevel,
  }) {
    return OnboardingProfile(
      sex: sex != null ? sex() : this.sex,
      birthYear: birthYear != null ? birthYear() : this.birthYear,
      heightCm: heightCm != null ? heightCm() : this.heightCm,
      weightKg: weightKg != null ? weightKg() : this.weightKg,
      activityLevel: activityLevel != null
          ? activityLevel()
          : this.activityLevel,
    );
  }

  static OnboardingProfile fromJson(Map<String, dynamic> json) {
    T? find<T extends Enum>(String key, List<T> values) {
      final name = json[key] as String?;
      if (name == null) return null;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    return OnboardingProfile(
      sex: find('sex', ProfileSex.values),
      birthYear: (json['birthYear'] as num?)?.toInt(),
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      activityLevel: find('activityLevel', ActivityLevel.values),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (sex != null) 'sex': sex!.name,
    if (birthYear != null) 'birthYear': birthYear,
    if (heightCm != null) 'heightCm': heightCm,
    if (weightKg != null) 'weightKg': weightKg,
    if (activityLevel != null) 'activityLevel': activityLevel!.name,
  };

  @override
  bool operator ==(Object other) =>
      other is OnboardingProfile &&
      other.sex == sex &&
      other.birthYear == birthYear &&
      other.heightCm == heightCm &&
      other.weightKg == weightKg &&
      other.activityLevel == activityLevel;

  @override
  int get hashCode =>
      Object.hash(sex, birthYear, heightCm, weightKg, activityLevel);

  @override
  String toString() =>
      'OnboardingProfile($sex, $birthYear, ${heightCm}cm, ${weightKg}kg, $activityLevel)';
}

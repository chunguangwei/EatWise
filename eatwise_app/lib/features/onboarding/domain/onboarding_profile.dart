/// onboarding 档案采集（阶段 A：性别/出生年/身高/体重/活动水平；
/// 阶段 B：减重目标体重/目标日期 + 进食障碍筛查）。
///
/// D-18：身高体重属敏感个人信息——整页可跳过、单项可留空，
/// 空项在营养计算中按缺失走 §1.6 兜底。
library;

import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';

/// 生理性别采集项（比 [Sex] 多「不透露」：不透露 = 公式按缺失兜底）。
enum ProfileSex { male, female, undisclosed }

/// 进食障碍筛查作答（阶段 B，敏感信息——仅存本地，不上报服务端）。
/// yes = 有进食障碍史或正在治疗 → 强制温和目标（周速率 ≤0.5 kg）；
/// preferNotToSay / no / 未作答 均不触发温和化。
enum EatingDisorderScreening { yes, no, preferNotToSay }

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
    this.eatingDisorderScreening,
    this.targetWeightKg,
    this.targetDate,
  });

  /// 空档案（等价于「跳过档案页」）。
  static const OnboardingProfile empty = OnboardingProfile();

  final ProfileSex? sex;
  final int? birthYear;
  final double? heightCm;
  final double? weightKg;
  final ActivityLevel? activityLevel;

  /// 进食障碍筛查作答（阶段 B；仅存本地不上报，D-18 敏感信息）。
  final EatingDisorderScreening? eatingDisorderScreening;

  /// 阶段 B 减重目标：目标体重（kg，取值域同 [weightKg]）。
  final double? targetWeightKg;

  /// 阶段 B 减重目标：目标日期（本地日）。
  final LocalDate? targetDate;

  /// 是否一项都没填（筛查与减重目标不计入——它们单独存在时没有计算意义）。
  bool get isEmpty =>
      sex == null &&
      birthYear == null &&
      heightCm == null &&
      weightKg == null &&
      activityLevel == null;

  /// 是否填了减重目标（目标页展示条件之一：还需 Q1=减脂且有体重）。
  bool get hasWeightGoal => targetWeightKg != null && targetDate != null;

  /// 转 TDEE 计算输入（§1.1）：不透露/缺失的性别 → null（兜底 2000 kcal）；
  /// 出生年 → 年龄（currentYear − birthYear，越域由 [UserProfileInput]
  /// 取值域判定按缺失处理）。阶段 B：减重目标与温和化标记透传，
  /// [today] 为缺口法的基准日（缺省不启用缺口法）。
  UserProfileInput toProfileInput({
    required NutritionGoalType goal,
    required int currentYear,
    LocalDate? today,
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
      targetWeightKg: targetWeightKg,
      targetDate: targetDate,
      today: today,
      gentleWeightLoss: eatingDisorderScreening == EatingDisorderScreening.yes,
    );
  }

  OnboardingProfile copyWith({
    ProfileSex? Function()? sex,
    int? Function()? birthYear,
    double? Function()? heightCm,
    double? Function()? weightKg,
    ActivityLevel? Function()? activityLevel,
    EatingDisorderScreening? Function()? eatingDisorderScreening,
    double? Function()? targetWeightKg,
    LocalDate? Function()? targetDate,
  }) {
    return OnboardingProfile(
      sex: sex != null ? sex() : this.sex,
      birthYear: birthYear != null ? birthYear() : this.birthYear,
      heightCm: heightCm != null ? heightCm() : this.heightCm,
      weightKg: weightKg != null ? weightKg() : this.weightKg,
      activityLevel: activityLevel != null
          ? activityLevel()
          : this.activityLevel,
      eatingDisorderScreening: eatingDisorderScreening != null
          ? eatingDisorderScreening()
          : this.eatingDisorderScreening,
      targetWeightKg: targetWeightKg != null
          ? targetWeightKg()
          : this.targetWeightKg,
      targetDate: targetDate != null ? targetDate() : this.targetDate,
    );
  }

  static LocalDate? _parseDate(String? iso) {
    if (iso == null) return null;
    final parts = iso.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return LocalDate(y, m, d);
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
      eatingDisorderScreening: find(
        'eatingDisorderScreening',
        EatingDisorderScreening.values,
      ),
      targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
      targetDate: _parseDate(json['targetDate'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (sex != null) 'sex': sex!.name,
    if (birthYear != null) 'birthYear': birthYear,
    if (heightCm != null) 'heightCm': heightCm,
    if (weightKg != null) 'weightKg': weightKg,
    if (activityLevel != null) 'activityLevel': activityLevel!.name,
    if (eatingDisorderScreening != null)
      'eatingDisorderScreening': eatingDisorderScreening!.name,
    if (targetWeightKg != null) 'targetWeightKg': targetWeightKg,
    if (targetDate != null) 'targetDate': targetDate!.toIsoString(),
  };

  @override
  bool operator ==(Object other) =>
      other is OnboardingProfile &&
      other.sex == sex &&
      other.birthYear == birthYear &&
      other.heightCm == heightCm &&
      other.weightKg == weightKg &&
      other.activityLevel == activityLevel &&
      other.eatingDisorderScreening == eatingDisorderScreening &&
      other.targetWeightKg == targetWeightKg &&
      other.targetDate == targetDate;

  @override
  int get hashCode => Object.hash(
    sex,
    birthYear,
    heightCm,
    weightKg,
    activityLevel,
    eatingDisorderScreening,
    targetWeightKg,
    targetDate,
  );

  @override
  String toString() =>
      'OnboardingProfile($sex, $birthYear, ${heightCm}cm, ${weightKg}kg, '
      '$activityLevel, screening=$eatingDisorderScreening, '
      'target=${targetWeightKg}kg@$targetDate)';
}

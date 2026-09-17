import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// 档案采集领域纯函数（阶段 A）：取值域校验 + 转 TDEE 计算输入
/// （「不透露」性别 → null 走 §1.6 兜底 2000 kcal）。
void main() {
  group('取值域校验', () {
    test('出生年：1920–今年（含边界）', () {
      expect(isValidBirthYear(1920, 2026), isTrue);
      expect(isValidBirthYear(2026, 2026), isTrue);
      expect(isValidBirthYear(1919, 2026), isFalse);
      expect(isValidBirthYear(2027, 2026), isFalse);
    });

    test('身高/体重：§1.1 取值域', () {
      expect(isValidHeightCm(100), isTrue);
      expect(isValidHeightCm(250), isTrue);
      expect(isValidHeightCm(99.9), isFalse);
      expect(isValidWeightKg(25), isTrue);
      expect(isValidWeightKg(300), isTrue);
      expect(isValidWeightKg(24.9), isFalse);
    });
  });

  group('toProfileInput', () {
    test('全字段映射：出生年 → 年龄（currentYear − birthYear）', () {
      const profile = OnboardingProfile(
        sex: ProfileSex.female,
        birthYear: 1998,
        heightCm: 162,
        weightKg: 55,
        activityLevel: ActivityLevel.sedentary,
      );
      final input = profile.toProfileInput(
        goal: NutritionGoalType.lose,
        currentYear: 2026,
      );
      expect(input.sex, Sex.female);
      expect(input.age, 28);
      expect(input.heightCm, 162);
      expect(input.weightKg, 55);
      expect(input.activityLevel, ActivityLevel.sedentary);
      expect(input.goal, NutritionGoalType.lose);
      expect(input.isComplete, isTrue);
    });

    test('「不透露」性别 → sex=null，全参其余齐备也走兜底 2000 kcal', () {
      const profile = OnboardingProfile(
        sex: ProfileSex.undisclosed,
        birthYear: 1998,
        heightCm: 162,
        weightKg: 55,
        activityLevel: ActivityLevel.sedentary,
      );
      final goal = computeNutritionGoal(
        profile.toProfileInput(
          goal: NutritionGoalType.maintain,
          currentYear: 2026,
        ),
        NutritionRuleConfig.defaults,
      );
      expect(goal.usedFallback, isTrue);
      expect(goal.targetKcal, 2000); // 性别缺失兜底（§1.6，双端口径 2000）
    });

    test('空档案 → 全空输入（兜底）', () {
      final input = OnboardingProfile.empty.toProfileInput(
        goal: NutritionGoalType.maintain,
        currentYear: 2026,
      );
      expect(input.isComplete, isFalse);
      expect(input.sex, isNull);
      expect(input.age, isNull);
    });
  });

  group('JSON 往返', () {
    test('非空档案 toJson/fromJson 相等；缺字段容忍', () {
      const profile = OnboardingProfile(
        sex: ProfileSex.male,
        birthYear: 1990,
        heightCm: 176,
        weightKg: 75,
        activityLevel: ActivityLevel.light,
      );
      expect(OnboardingProfile.fromJson(profile.toJson()), profile);
      expect(
        OnboardingProfile.fromJson(const <String, dynamic>{'birthYear': 1990}),
        const OnboardingProfile(birthYear: 1990),
      );
      // 未知枚举名按缺失处理（防御旧版本脏数据）。
      expect(
        OnboardingProfile.fromJson(const <String, dynamic>{
          'sex': 'unknown',
          'activityLevel': 'x',
        }),
        OnboardingProfile.empty,
      );
    });
  });
}

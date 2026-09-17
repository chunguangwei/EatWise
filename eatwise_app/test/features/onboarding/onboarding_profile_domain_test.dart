import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// 档案采集领域纯函数（阶段 A：取值域校验 + 转 TDEE 计算输入，
/// 「不透露」性别 → null 走 §1.6 兜底 2000 kcal；阶段 B：筛查温和化标记 /
/// 减重目标透传与 PATCH 映射 / JSON 往返兼容）。
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

    test('阶段 B 字段（筛查/目标体重/目标日期）参与往返；旧版 JSON 无这些键容忍', () {
      final profile = OnboardingProfile(
        sex: ProfileSex.female,
        weightKg: 70,
        eatingDisorderScreening: EatingDisorderScreening.preferNotToSay,
        targetWeightKg: 60,
        targetDate: const LocalDate(2026, 12, 1),
      );
      expect(OnboardingProfile.fromJson(profile.toJson()), profile);
      // 非法日期串按未设置处理（防御）。
      expect(
        OnboardingProfile.fromJson(const <String, dynamic>{
          'targetDate': 'not-a-date',
        }).targetDate,
        isNull,
      );
    });
  });

  group('阶段 B：筛查与减重目标映射', () {
    test('筛查「是」→ gentleWeightLoss=true；其余作答不温和化', () {
      const base = OnboardingProfile(weightKg: 70);
      for (final (answer, expected) in <(EatingDisorderScreening?, bool)>[
        (EatingDisorderScreening.yes, true),
        (EatingDisorderScreening.no, false),
        (EatingDisorderScreening.preferNotToSay, false),
        (null, false),
      ]) {
        final input = base
            .copyWith(eatingDisorderScreening: () => answer)
            .toProfileInput(goal: NutritionGoalType.lose, currentYear: 2026);
        expect(input.gentleWeightLoss, expected, reason: '$answer');
      }
    });

    test('减重目标透传：targetWeightKg/targetDate/today 进入计算输入', () {
      const today = LocalDate(2026, 9, 17);
      final input =
          const OnboardingProfile(
            weightKg: 70,
            targetWeightKg: 60,
            targetDate: LocalDate(2026, 12, 1),
          ).toProfileInput(
            goal: NutritionGoalType.lose,
            currentYear: 2026,
            today: today,
          );
      expect(input.targetWeightKg, 60);
      expect(input.targetDate, const LocalDate(2026, 12, 1));
      expect(input.today, today);
    });

    test('serverProfilePatch：缺省空目标不传；includeNullTargets 显式传 null（可清空）', () {
      const empty = OnboardingProfile.empty;
      expect(serverProfilePatch(empty).containsKey('targetWeightKg'), isFalse);
      expect(serverProfilePatch(empty).containsKey('targetDate'), isFalse);
      final cleared = serverProfilePatch(empty, includeNullTargets: true);
      expect(cleared['targetWeightKg'], isNull);
      expect(cleared['targetDate'], isNull);

      final withGoal = serverProfilePatch(
        const OnboardingProfile(
          targetWeightKg: 60,
          targetDate: LocalDate(2026, 12, 1),
        ),
      );
      expect(withGoal['targetWeightKg'], 60);
      expect(withGoal['targetDate'], '2026-12-01');
      // 筛查作答不上报（敏感信息仅存本地）。
      final withScreening = serverProfilePatch(
        const OnboardingProfile(
          eatingDisorderScreening: EatingDisorderScreening.yes,
        ),
      );
      expect(withScreening.containsKey('eatingDisorderScreening'), isFalse);
    });
  });
}

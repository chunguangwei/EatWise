import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/settings/domain/profile_completeness.dart';
import 'package:flutter_test/flutter_test.dart';

/// 档案完善度纯函数（薄荷走查 P3）：7 项口径，已填/总数 → 百分比。
void main() {
  group('profileCompleteness（7 项口径）', () {
    test('空档案：0 项已填 → 0%', () {
      const profile = OnboardingProfile.empty;
      expect(profileCompletenessFilled(profile), 0);
      expect(profileCompletenessPercent(profile), 0);
    });

    test('部分填写：性别+身高+体重 → 3/7 ≈ 43%', () {
      const profile = OnboardingProfile(
        sex: ProfileSex.female,
        heightCm: 162,
        weightKg: 55,
      );
      expect(profileCompletenessFilled(profile), 3);
      expect(profileCompletenessPercent(profile), 43);
    });

    test('筛查作答不计入（敏感信息不催填）', () {
      const profile = OnboardingProfile(
        eatingDisorderScreening: EatingDisorderScreening.no,
      );
      expect(profileCompletenessFilled(profile), 0);
      expect(profileCompletenessPercent(profile), 0);
    });

    test('目标只填一项：目标体重/目标日期分别计项', () {
      const onlyWeight = OnboardingProfile(targetWeightKg: 50);
      expect(profileCompletenessFilled(onlyWeight), 1);
      const onlyDate = OnboardingProfile(targetDate: LocalDate(2026, 12, 1));
      expect(profileCompletenessFilled(onlyDate), 1);
    });

    test('全部 7 项 → 100%（UI 不渲染进度条的阈值）', () {
      const profile = OnboardingProfile(
        sex: ProfileSex.male,
        birthYear: 1990,
        heightCm: 176,
        weightKg: 75,
        activityLevel: ActivityLevel.light,
        targetWeightKg: 70,
        targetDate: LocalDate(2026, 12, 1),
      );
      expect(profileCompletenessFilled(profile), profileCompletenessTotal);
      expect(profileCompletenessPercent(profile), 100);
    });
  });
}

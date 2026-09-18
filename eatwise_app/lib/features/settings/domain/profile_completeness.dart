/// 档案完善度（薄荷走查 P3：对标薄荷健康档案 39% 进度条，游戏化补齐引导）。
///
/// 口径：7 项采集项——性别 / 出生年 / 身高 / 体重 / 活动水平 / 目标体重 /
/// 目标日期；统计已填（非 null）项数占比。进食障碍筛查不计入（敏感信息，
/// 不作游戏化催填）。纯函数，UI 只做接线。
library;

import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';

/// 完善度统计总项数（性别/出生年/身高/体重/活动水平/目标体重/目标日期）。
const int profileCompletenessTotal = 7;

/// 已填项数（0–[profileCompletenessTotal]）。
int profileCompletenessFilled(OnboardingProfile profile) {
  return <Object?>[
    profile.sex,
    profile.birthYear,
    profile.heightCm,
    profile.weightKg,
    profile.activityLevel,
    profile.targetWeightKg,
    profile.targetDate,
  ].where((field) => field != null).length;
}

/// 完善度百分比（0–100，四舍五入；100% 时 UI 不再渲染进度条）。
int profileCompletenessPercent(OnboardingProfile profile) {
  return (profileCompletenessFilled(profile) / profileCompletenessTotal * 100)
      .round();
}

import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart'
    show weightTargetProvider;
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart' show UserMeView;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 身体档案保存服务（阶段 A，「我的-身体档案」）：本地落盘 + 营养目标
/// 当日重算（D-04，历史不回溯）+ 登录态 U2 PATCH（失败抛 ApiException
/// 由 UI 提示，本地保存不回滚〔最简可靠〕）。
final class BodyProfileService {
  const BodyProfileService(this._ref);

  final Ref _ref;

  OnboardingStore get _store => _ref.read(onboardingStoreProvider);

  /// 表单初值（[me] 为已解析的服务端档案，未登录/未加载完传 null）：
  /// 本地已采集档案优先；本地为空时回落服务端档案。
  OnboardingProfile initialProfile(UserMeView? me) {
    final local = _store.loadProfile();
    if (local != null && !local.isEmpty) return local;
    if (me == null) return local ?? OnboardingProfile.empty;
    return OnboardingProfile(
      sex: switch (me.gender) {
        'male' => ProfileSex.male,
        'female' => ProfileSex.female,
        _ => null,
      },
      birthYear: me.birthYear,
      heightCm: me.heightCm,
      weightKg: me.weightKg,
      activityLevel: _activityOf(me.activityLevel),
      targetWeightKg: me.targetWeightKg,
      targetDate: _parseTargetDate(me.targetDate),
    );
  }

  /// 保存：本地档案 + 重算营养目标落盘并刷新目标 Provider；
  /// 已登录再 PATCH（档案字段，字段级 LWW；减重目标显式传 null 支持清空）。
  Future<NutritionGoalSnapshot> save(OnboardingProfile profile) async {
    // 筛查作答仅存本地且不在本表单内编辑——保留已存值，不被表单保存抹掉。
    final screening =
        profile.eatingDisorderScreening ??
        _store.loadProfile()?.eatingDisorderScreening;
    final merged = profile.copyWith(eatingDisorderScreening: () => screening);
    _store.saveProfile(merged);
    final goal = _recomputeGoal(merged);
    _ref.invalidate(nutritionGoalProvider);
    // 体重目标线（阶段 C）：档案保存后趋势页目标参考线即刻刷新。
    _ref.invalidate(weightTargetProvider);
    if (_isLoggedIn()) {
      await _ref
          .read(userApiProvider)
          .patchMe(serverProfilePatch(merged, includeNullTargets: true));
      _ref.invalidate(userMeProvider);
    }
    return goal;
  }

  NutritionGoalSnapshot _recomputeGoal(OnboardingProfile profile) {
    // 目标类型：服务端档案 goal 优先（fat_loss → lose），否则维持。
    final serverGoal = _ref.read(userMeProvider).value?.goal;
    final goalType = serverGoal == 'fat_loss'
        ? NutritionGoalType.lose
        : NutritionGoalType.maintain;
    final nowUtc = _ref.read(nowUtcProvider);
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      nowUtc * 1000,
      isUtc: true,
    ).year;
    final goal = computeNutritionGoal(
      profile.toProfileInput(
        goal: goalType,
        currentYear: currentYear,
        // 阶段 B 缺口法基准日（设备时区本地日）。
        today: localDateOf(nowUtc, _ref.read(deviceLocationProvider)),
      ),
      NutritionRuleConfig.defaults,
    );
    final snapshot = NutritionGoalSnapshot(
      targetKcal: goal.targetKcal,
      proteinG: goal.proteinG,
      carbG: goal.carbG,
      fatG: goal.fatG,
      usedFallback: goal.usedFallback,
      configVersion: goal.configVersion,
      weeklyRateKg: goal.weightLoss?.weeklyRateKg,
      weightLossClamped: goal.weightLoss?.clamped ?? false,
      reachDate: goal.weightLoss?.reachDate.toIsoString(),
    );
    _store.saveNutritionGoal(snapshot);
    return snapshot;
  }

  bool _isLoggedIn() {
    try {
      return _ref.read(authControllerProvider).status == AuthStatus.loggedIn;
    } on Object {
      return false; // 认证未装配的测试环境按未登录处理
    }
  }

  static ActivityLevel? _activityOf(String? name) {
    for (final level in ActivityLevel.values) {
      if (level.name == name) return level;
    }
    return null;
  }

  /// 服务端目标日期（YYYY-MM-DD）→ LocalDate；非法串按未设置处理。
  static LocalDate? _parseTargetDate(String? iso) {
    if (iso == null) return null;
    final parts = iso.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return LocalDate(y, m, d);
  }
}

/// 身体档案服务 Provider。
final bodyProfileServiceProvider = Provider<BodyProfileService>((ref) {
  return BodyProfileService(ref);
});

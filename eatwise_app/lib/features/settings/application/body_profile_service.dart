import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
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
    );
  }

  /// 保存：本地档案 + 重算营养目标落盘并刷新目标 Provider；
  /// 已登录再 PATCH（档案字段，字段级 LWW）。
  Future<NutritionGoalSnapshot> save(OnboardingProfile profile) async {
    _store.saveProfile(profile);
    final goal = _recomputeGoal(profile);
    _ref.invalidate(nutritionGoalProvider);
    if (_isLoggedIn()) {
      await _ref.read(userApiProvider).patchMe(serverProfilePatch(profile));
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
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      _ref.read(nowUtcProvider) * 1000,
      isUtc: true,
    ).year;
    final goal = computeNutritionGoal(
      profile.toProfileInput(goal: goalType, currentYear: currentYear),
      NutritionRuleConfig.defaults,
    );
    final snapshot = NutritionGoalSnapshot(
      targetKcal: goal.targetKcal,
      proteinG: goal.proteinG,
      carbG: goal.carbG,
      fatG: goal.fatG,
      usedFallback: goal.usedFallback,
      configVersion: goal.configVersion,
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
}

/// 身体档案服务 Provider。
final bodyProfileServiceProvider = Provider<BodyProfileService>((ref) {
  return BodyProfileService(ref);
});

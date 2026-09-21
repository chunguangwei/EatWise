import 'dart:async';

import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// onboarding 档案/引导状态云端同步（阶段 A，U2 PATCH /users/me）。
///
/// 登录态下尽力而为：失败静默（不阻塞本地引导流程，〔假设〕不重试——
/// 下次登录由服务端 onboardingStatus 下行同步兜底校正，见
/// AuthController._applySession）。未登录为 no-op。

/// 同步动作抽象（测试可换记录型假实现）。
abstract interface class ProfileSyncService {
  /// onboarding 完成（一键启动）：档案字段 + 问卷目标 + onboardingStatus。
  void syncOnboardingCompleted({
    required OnboardingProfile? profile,
    required GoalAnswer? goal,
  });

  /// onboarding 跳过（问卷「跳过，先看看」）。
  void syncOnboardingSkipped();
}

/// 问卷目标 → 服务端 goal 枚举（schema.prisma：fat_loss/health_metric/routine/trial）。
String? serverGoalOf(GoalAnswer? goal) {
  return switch (goal) {
    GoalAnswer.loseWeight => 'fat_loss',
    GoalAnswer.improveHealth => 'health_metric',
    GoalAnswer.adjustSchedule => 'routine',
    GoalAnswer.justTrying => 'trial',
    null => null,
  };
}

/// 档案 → PATCH 字段（空项不传，字段级 LWW 由服务端保留既有值；
/// 「不透露」性别不上报；进食障碍筛查属敏感信息仅存本地不上报）。
///
/// 阶段 B 减重目标（targetWeightKg/targetDate）：缺省同样空项不传；
/// [includeNullTargets]=true 时显式传 null（设置页「可清空」语义）。
Map<String, Object?> serverProfilePatch(
  OnboardingProfile profile, {
  bool includeNullTargets = false,
}) {
  return <String, Object?>{
    if (profile.sex == ProfileSex.male) 'gender': 'male',
    if (profile.sex == ProfileSex.female) 'gender': 'female',
    if (profile.birthYear != null) 'birthYear': profile.birthYear,
    if (profile.heightCm != null) 'heightCm': profile.heightCm,
    if (profile.weightKg != null) 'weightKg': profile.weightKg,
    if (profile.activityLevel != null)
      'activityLevel': profile.activityLevel!.name,
    if (profile.targetWeightKg != null || includeNullTargets)
      'targetWeightKg': profile.targetWeightKg,
    if (profile.targetDate != null || includeNullTargets)
      'targetDate': profile.targetDate?.toIsoString(),
  };
}

/// 服务端活动水平枚举名 → [ActivityLevel]；未知/缺失 null。
ActivityLevel? activityLevelOf(String? name) {
  for (final level in ActivityLevel.values) {
    if (level.name == name) return level;
  }
  return null;
}

/// 服务端档案（U1 userView）→ 本地档案（`serverProfilePatch` 的逆解析）：
/// 跨设备登录/重装后本地未落盘时的下行回落（走查修复 v1.13.3：营养目标
/// provider 用它在本地快照缺失时按服务端档案重算，避免误显示「默认目标」
/// 提示）。进食障碍筛查敏感仅本地，无对应字段。
OnboardingProfile serverProfileOf(UserMeView me) {
  return OnboardingProfile(
    sex: switch (me.gender) {
      'male' => ProfileSex.male,
      'female' => ProfileSex.female,
      _ => null,
    },
    birthYear: me.birthYear,
    heightCm: me.heightCm,
    weightKg: me.weightKg,
    activityLevel: activityLevelOf(me.activityLevel),
    targetWeightKg: me.targetWeightKg,
    targetDate: parseLocalDate(me.targetDate),
  );
}

/// 服务端日期串（YYYY-MM-DD）→ LocalDate；非法串按未设置处理。
LocalDate? parseLocalDate(String? iso) {
  if (iso == null) return null;
  final parts = iso.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return LocalDate(y, m, d);
}

/// 档案字段级合并：本地非空字段优先，缺失项回落服务端（重装/跨设备
/// 登录下行回落；走查修复 v1.13.3）。进食障碍筛查仅存本地，直接沿用。
OnboardingProfile mergeProfileWithServer(
  OnboardingProfile local,
  OnboardingProfile? remote,
) {
  if (remote == null) return local;
  return OnboardingProfile(
    sex: local.sex ?? remote.sex,
    birthYear: local.birthYear ?? remote.birthYear,
    heightCm: local.heightCm ?? remote.heightCm,
    weightKg: local.weightKg ?? remote.weightKg,
    activityLevel: local.activityLevel ?? remote.activityLevel,
    eatingDisorderScreening: local.eatingDisorderScreening,
    targetWeightKg: local.targetWeightKg ?? remote.targetWeightKg,
    targetDate: local.targetDate ?? remote.targetDate,
  );
}

/// U2 真实实现（失败静默）。
final class RemoteProfileSyncService implements ProfileSyncService {
  const RemoteProfileSyncService(this._api, this._isLoggedIn);

  final UserApi _api;
  final bool Function() _isLoggedIn;
  @override
  void syncOnboardingCompleted({
    required OnboardingProfile? profile,
    required GoalAnswer? goal,
  }) {
    _fireAndForget(<String, Object?>{
      'onboardingStatus': 'completed',
      if (profile != null) ...serverProfilePatch(profile),
      if (serverGoalOf(goal) != null) 'goal': serverGoalOf(goal),
    });
  }

  @override
  void syncOnboardingSkipped() {
    _fireAndForget(const <String, Object?>{'onboardingStatus': 'skipped'});
  }

  void _fireAndForget(Map<String, Object?> patch) {
    if (!_isLoggedIn()) return;
    unawaited(_send(patch));
  }

  Future<void> _send(Map<String, Object?> patch) async {
    try {
      await _api.patchMe(patch);
    } on Object catch (e) {
      // 失败静默：不阻塞本地流程、不重试（下次登录下行校正）。
      debugPrint('ProfileSyncService: PATCH /users/me 失败（已忽略） $e');
    }
  }
}

/// 同步服务 Provider（未登录 no-op；测试 override 为假实现断言调用）。
final profileSyncServiceProvider = Provider<ProfileSyncService>((ref) {
  return RemoteProfileSyncService(UserApi(ref.watch(apiDioProvider)), () {
    try {
      return ref.read(authControllerProvider).status == AuthStatus.loggedIn;
    } on Object {
      return false; // 认证未装配的测试/演示环境按未登录处理
    }
  });
});

import 'dart:async';
import 'dart:convert';

import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// onboarding 档案/引导状态云端同步（阶段 A，U2 PATCH /users/me）。
///
/// 脏标记制（v1.13.31，与 FastingPlanSync 同口径——此前 fire-and-forget
/// 无重试，离线瞬间上行失败则服务端永无档案，换机无值可回落）：
/// 任何档案/引导状态写入先落 prefs 脏键 `profile_dirty_<userId>`
/// （键级 LWW 合并），再尽力即时上行；失败保留脏键，由
/// RecordSyncEngine.syncNow 每轮 [flushDirty] 重试。匿名期脏键在登录后
/// 首轮同步迁移到真实 uid（与方案/延长队列同口径）。

/// 同步动作抽象（测试可换记录型假实现）。
abstract interface class ProfileSyncService {
  /// onboarding 完成（一键启动）：档案字段 + 问卷目标 + onboardingStatus。
  void syncOnboardingCompleted({
    required OnboardingProfile? profile,
    required GoalAnswer? goal,
  });

  /// onboarding 跳过（问卷「跳过，先看看」）。
  void syncOnboardingSkipped();

  /// 置脏 + 尽力即时上行（设置页保存路径的兜底：UI 报错行为不变，同步
  /// 链负责最终收敛）。
  void markDirtyAndTryFlush(Map<String, Object?> patch);

  /// 同步轮重试入口（RecordSyncEngine.syncNow 挂接）：脏键存在时 PATCH，
  /// 成功按 compare-and-delete 清脏，失败保留下轮。未登录 no-op。
  Future<void> flushDirty();
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

/// U2 真实实现（脏标记制：失败保留重试，见文件头注释）。
final class RemoteProfileSyncService implements ProfileSyncService {
  const RemoteProfileSyncService(
    this._patchMe,
    this._isLoggedIn,
    this._prefs,
    this._userId,
  );

  /// PATCH /users/me 通道（生产 `UserApi.patchMe`；测试注入假实现）。
  final Future<UserMeView> Function(Map<String, Object?> patch) _patchMe;
  final bool Function() _isLoggedIn;
  final SharedPreferences _prefs;
  final String Function() _userId;

  /// 脏键前缀（用户命名空间；匿名期落 `profile_dirty_anonymous`，登录后
  /// 首轮 flush 迁移到真实 uid——与 FastingPlanSync 登录迁移同口径）。
  static const String _dirtyPrefix = 'profile_dirty_';

  String _dirtyKey(String uid) => '$_dirtyPrefix$uid';

  /// 键级 LWW 合并落脏（后写键覆盖先写键，其余键保留）。
  void _markDirty(Map<String, Object?> patch) {
    final key = _dirtyKey(_userId());
    final raw = _prefs.getString(key);
    final merged = <String, Object?>{
      if (raw != null)
        ...(jsonDecode(raw) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v),
        ),
      ...patch,
    };
    unawaited(_prefs.setString(key, jsonEncode(merged)));
  }

  @override
  void syncOnboardingCompleted({
    required OnboardingProfile? profile,
    required GoalAnswer? goal,
  }) {
    markDirtyAndTryFlush(<String, Object?>{
      'onboardingStatus': 'completed',
      if (profile != null) ...serverProfilePatch(profile),
      if (serverGoalOf(goal) != null) 'goal': serverGoalOf(goal),
    });
  }

  @override
  void syncOnboardingSkipped() {
    markDirtyAndTryFlush(const <String, Object?>{
      'onboardingStatus': 'skipped',
    });
  }

  @override
  void markDirtyAndTryFlush(Map<String, Object?> patch) {
    _markDirty(patch);
    if (!_isLoggedIn()) return; // 匿名/离线：脏保留，登录后首轮同步迁移上行
    unawaited(flushDirty());
  }

  @override
  Future<void> flushDirty() async {
    final uid = _userId();
    if (uid == 'anonymous') return; // 匿名 PATCH 必 401：脏保留待登录迁移
    final key = _dirtyKey(uid);
    var raw = _prefs.getString(key);
    if (raw == null) {
      // 登录迁移：匿名期写入的脏档案换挂真实 uid 后上行。
      final anonKey = _dirtyKey('anonymous');
      raw = _prefs.getString(anonKey);
      if (raw == null) return;
      await _prefs.setString(key, raw);
      await _prefs.remove(anonKey);
    }
    final Map<String, Object?> patch;
    try {
      patch = Map<String, Object?>.from(jsonDecode(raw) as Map);
    } on Object {
      await _prefs.remove(key); // 脏数据损坏：清键，等下次写入重落
      return;
    }
    if (patch.isEmpty) {
      await _prefs.remove(key);
      return;
    }
    try {
      await _patchMe(patch);
      // compare-and-delete：PATCH 在途期间又有新写入（raw 被覆写）时
      // 保留脏键给下一轮，绝不误擦未上行的新档案。
      if (_prefs.getString(key) == raw) {
        await _prefs.remove(key);
      }
    } on Object catch (e) {
      // 失败保留脏键（网络/4xx/5xx 一律下轮重试；字段级校验问题由
      // 服务端 DTO 白名单 + 契约测试防线兜底，不产生永败组合）。
      debugPrint('ProfileSyncService: 档案上行失败（保留脏标记，下轮重试） $e');
    }
  }
}

/// 同步服务 Provider（未登录 no-op；测试 override 为假实现断言调用）。
final profileSyncServiceProvider = Provider<ProfileSyncService>((ref) {
  final api = UserApi(ref.watch(apiDioProvider));
  return RemoteProfileSyncService(
    api.patchMe,
    () {
      try {
        return ref.read(authControllerProvider).status == AuthStatus.loggedIn;
      } on Object {
        return false; // 认证未装配的测试/演示环境按未登录处理
      }
    },
    ref.watch(sharedPreferencesProvider),
    () {
      try {
        return ref.read(authControllerProvider).userId ?? 'anonymous';
      } on Object {
        return 'anonymous';
      }
    },
  );
});

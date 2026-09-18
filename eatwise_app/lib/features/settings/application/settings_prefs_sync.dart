import 'package:eatwise/features/account/application/weight_unit_controller.dart';
import 'package:eatwise/features/account/domain/weight_unit.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/health/domain/exercise_goals.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-21 用户级偏好跨端同步（随账号走；设备级状态——AI 配置/模型下载/
/// 健康授权/通知权限/账号标识缓存——留本机不进同步包）。
///
/// 同步包键约定：`{locale, theme, weightUnit, burnGoalKcal, stepsGoal,
/// syncedAt}`。版本兼容策略：新增键只能追加，pull 应用时**缺键跳过**、
/// 不识别/非法值忽略（旧端收到新键不动对应偏好）。
///
/// - push：偏好变更后整包 PATCH /users/me `{settingsPrefs: ...}`（服务端
///   字段级 LWW 整包替换），失败静默——离线不阻塞 UI，下次变更/启动再推。
/// - pull：登录成功 / 启动恢复会话后调用；远端 `syncedAt` 比本地
///   lastPrefsSyncedAt 新才把各值应用到本地 provider，缺键不动。
/// - 回环防护：pull 应用期间 [SettingsPrefsSync.applying]=true，
///   setter 触发的 push 直接跳过。

/// 本地记录的最近一次同步包时间戳（SharedPreferences 键）。
const String lastPrefsSyncedAtKey = 'settings.lastPrefsSyncedAt';

/// 偏好同步协调器（依赖全部回调注入，单测可换记录型假实现）。
final class SettingsPrefsSync {
  SettingsPrefsSync({
    required this.api,
    required this.isLoggedIn,
    required this.collectLocal,
    required this.applyRemote,
    required this.readLastSyncedAt,
    required this.saveLastSyncedAt,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 用户端点（复用 U2 patchMe 通道）。
  final UserApi api;

  /// 登录态判定（未登录 push/pull 均 no-op）。
  final bool Function() isLoggedIn;

  /// 当前本地偏好 → 同步包（键约定见文件头注释）。
  final Map<String, Object?> Function() collectLocal;

  /// 远端同步包 → 本地偏好（缺键跳过，不识别/非法值忽略）。
  final void Function(Map<String, dynamic> prefs) applyRemote;

  /// 本地记录的最近一次同步包时间戳。
  final DateTime? Function() readLastSyncedAt;

  /// 持久化最近一次同步包时间戳。
  final Future<void> Function(DateTime at) saveLastSyncedAt;

  final DateTime Function() _now;

  bool _applying = false;

  /// pull 应用远端值期间为 true（此间 setter 触发的 push 跳过，防回环）。
  bool get applying => _applying;

  /// 偏好变更后整包上行（未登录 no-op；失败静默，下次再推）。
  Future<void> push() async {
    if (_applying) return; // pull 回写触发的变更不回推
    if (!isLoggedIn()) return;
    final syncedAt = _now().toUtc();
    try {
      await api.patchMe(<String, Object?>{
        'settingsPrefs': <String, Object?>{
          ...collectLocal(),
          'syncedAt': syncedAt.toIso8601String(),
        },
      });
      await saveLastSyncedAt(syncedAt);
    } on Object catch (e) {
      // 失败静默：离线场景下次变更/启动再推，不阻塞 UI。
      debugPrint('SettingsPrefsSync: 偏好上行失败（已忽略） $e');
    }
  }

  /// 登录成功 / 启动恢复会话后下行：远端更新才应用，缺键不动。
  Future<void> pull() async {
    if (!isLoggedIn()) return;
    try {
      final prefs = (await api.getMe()).settingsPrefs;
      if (prefs == null || prefs.isEmpty) return;
      final remoteAt = DateTime.tryParse(prefs['syncedAt'] as String? ?? '');
      final localAt = readLastSyncedAt();
      // 远端不新于本地 → 不覆盖；远端无时间戳仅在本地无记录时应用。
      if (localAt != null && (remoteAt == null || !remoteAt.isAfter(localAt))) {
        return;
      }
      _applying = true;
      try {
        applyRemote(prefs);
      } finally {
        _applying = false;
      }
      await saveLastSyncedAt(remoteAt ?? _now().toUtc());
    } on Object catch (e) {
      // 失败静默：本地偏好继续生效，下次登录/启动重试。
      debugPrint('SettingsPrefsSync: 偏好下行失败（已忽略） $e');
    }
  }
}

/// 当前本地偏好 → 同步包（键约定见文件头注释，新增键只能追加）。
Map<String, Object?> _collectLocalPrefs(Ref ref) {
  final goals = ref.read(exerciseGoalsProvider);
  return <String, Object?>{
    'locale': ref.read(languageModeProvider),
    'theme': ref.read(themeModeProvider).name,
    'weightUnit': ref.read(weightUnitProvider).name,
    'burnGoalKcal': goals.burnGoalKcal,
    'stepsGoal': goals.stepsGoal,
  };
}

/// 远端同步包 → 本地 provider（缺键跳过，不识别/非法值忽略）。
void _applyRemotePrefs(Ref ref, Map<String, dynamic> prefs) {
  final locale = prefs['locale'];
  if (locale is String &&
      (locale == LanguageModeController.system ||
          locale == LanguageModeController.zhCN ||
          locale == LanguageModeController.en)) {
    ref.read(languageModeProvider.notifier).setMode(locale);
  }
  final theme = prefs['theme'];
  if (theme is String) {
    final ThemeMode? mode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
    if (mode != null) ref.read(themeModeProvider.notifier).setMode(mode);
  }
  final unit = weightUnitFromName(prefs['weightUnit'] as String?);
  if (unit != null) ref.read(weightUnitProvider.notifier).setUnit(unit);
  final burn = prefs['burnGoalKcal'];
  if (burn is num && ExerciseGoals.isValidBurnGoal(burn.toDouble())) {
    // setter 内部立即落 state + 异步落盘，无需 await。
    // ignore: unawaited_futures
    ref.read(exerciseGoalsProvider.notifier).setBurnGoalKcal(burn.toDouble());
  }
  final steps = prefs['stepsGoal'];
  if (steps is num && ExerciseGoals.isValidStepsGoal(steps.toInt())) {
    // ignore: unawaited_futures
    ref.read(exerciseGoalsProvider.notifier).setStepsGoal(steps.toInt());
  }
}

SharedPreferences? _tryPrefs(Ref ref) {
  try {
    return ref.watch(sharedPreferencesProvider);
  } on Object {
    return null; // 未注入场景（测试/预览）仅内存生效。
  }
}

/// 偏好同步协调器 Provider：登录成功/启动恢复会话由挂接点调 [SettingsPrefsSync.pull]；
/// 四个偏好 provider 任一变更即整包 [SettingsPrefsSync.push]（pull 回写期间 applying
/// 防回环）。非 autoDispose，首次读取后常驻（push 监听随之生效）。
final settingsPrefsSyncProvider = Provider<SettingsPrefsSync>((ref) {
  final prefs = _tryPrefs(ref);
  final sync = SettingsPrefsSync(
    api: ref.watch(userApiProvider),
    isLoggedIn: () {
      try {
        return ref.read(authControllerProvider).status == AuthStatus.loggedIn;
      } on Object {
        return false; // 认证未装配的测试/演示环境按未登录处理
      }
    },
    collectLocal: () => _collectLocalPrefs(ref),
    applyRemote: (remote) => _applyRemotePrefs(ref, remote),
    readLastSyncedAt: () {
      final raw = prefs?.getString(lastPrefsSyncedAtKey);
      return raw == null ? null : DateTime.tryParse(raw);
    },
    saveLastSyncedAt: (at) async {
      await prefs?.setString(
        lastPrefsSyncedAtKey,
        at.toUtc().toIso8601String(),
      );
    },
  );
  ref
    ..listen<String>(languageModeProvider, (_, _) => sync.push())
    ..listen<ThemeMode>(themeModeProvider, (_, _) => sync.push())
    ..listen<WeightUnit>(weightUnitProvider, (_, _) => sync.push())
    ..listen<ExerciseGoals>(exerciseGoalsProvider, (_, _) => sync.push());
  return sync;
});

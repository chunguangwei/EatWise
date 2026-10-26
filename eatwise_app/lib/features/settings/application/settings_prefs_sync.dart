import 'dart:async';
import 'dart:convert';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/session_lease.dart';
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

/// D-21 用户级偏好跨端同步（随账号走；设备级状态留本机不进同步包）。
///
/// 同步包键约定：`{locale, theme, weightUnit, burnGoalKcal, stepsGoal,
/// syncedAt}`。新增键只能追加，pull 缺键跳过、非法值忽略。
/// 本地变更先保存按 uid 隔离的待上行快照，[SettingsPrefsSync.flushDirty]
/// 由同步轮重试；
/// 下行期间不置脏，本地有待上行快照时优先保留本地选择。
const String lastPrefsSyncedAtKey = 'settings.lastPrefsSyncedAt';

String lastPrefsSyncedAtKeyFor(String userId) =>
    '$lastPrefsSyncedAtKey.$userId';

String settingsPrefsDirtyKey(String userId) => 'settings.prefsDirty.$userId';

/// 偏好同步协调器（依赖全部回调注入，单测可换记录型假实现）。
final class SettingsPrefsSync {
  SettingsPrefsSync({
    required this.api,
    required this.isLoggedIn,
    required this.userId,
    required this.collectLocal,
    required this.applyRemote,
    required this.readDirtyPayload,
    required this.saveDirtyPayload,
    required this.readLastSyncedAt,
    required this.saveLastSyncedAt,
    DateTime Function()? now,
    this.captureSession,
  }) : _now = now ?? DateTime.now;

  final SessionLease? Function()? captureSession;

  Future<void> _inSession(Future<void> Function() work) async {
    final lease = SessionLease.current ?? captureSession?.call();
    try {
      if (lease == null) {
        await work();
      } else {
        await lease.run(work);
      }
    } on SessionChangedException {
      // Keep the original account's dirty snapshot for its next session.
    }
  }

  final UserApi api;
  final bool Function() isLoggedIn;
  final String Function() userId;
  final Map<String, Object?> Function() collectLocal;
  final void Function(Map<String, dynamic> prefs) applyRemote;
  final String? Function(String userId) readDirtyPayload;
  final Future<void> Function(String userId, String? payload) saveDirtyPayload;
  final DateTime? Function(String userId) readLastSyncedAt;
  final Future<void> Function(String userId, DateTime at) saveLastSyncedAt;

  final DateTime Function() _now;

  bool _applying = false;
  bool _flushRequested = false;
  Future<void>? _activeFlush;

  bool get applying => _applying;

  bool _isCurrentUser(String uid) => isLoggedIn() && userId() == uid;

  /// 本地变更先落待上行快照，再尽力上行；失败由 [flushDirty] 重试。
  Future<void> push() => _inSession(_push);

  Future<void> _push() async {
    checkActiveSession();
    if (_applying || !isLoggedIn()) return;
    final uid = userId();
    await saveDirtyPayload(uid, jsonEncode(collectLocal()));
    checkActiveSession();
    await flushDirty();
  }

  /// 同步轮重试入口；干净的账号不发请求。并发调用共享同一串行 flush，
  /// 在途期间的新快照会 trailing flush，避免旧响应覆盖新偏好。
  Future<void> flushDirty() {
    if (!isLoggedIn()) return Future<void>.value();
    _flushRequested = true;
    final active = _activeFlush;
    if (active != null) return active;

    final future = _inSession(_drainFlush);
    _activeFlush = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_activeFlush, future)) _activeFlush = null;
      }),
    );
    return future;
  }

  Future<void> _drainFlush() async {
    while (_flushRequested) {
      checkActiveSession();
      _flushRequested = false;
      if (!isLoggedIn()) return;
      final uid = userId();
      final raw = readDirtyPayload(uid);
      if (raw == null) continue;

      final Map<String, Object?> local;
      try {
        local = Map<String, Object?>.from(jsonDecode(raw) as Map);
      } on Object {
        await saveDirtyPayload(uid, null);
        continue;
      }
      final syncedAt = _now().toUtc();
      try {
        final me = await api.patchMe(<String, Object?>{
          'settingsPrefs': <String, Object?>{
            ...local,
            'syncedAt': syncedAt.toIso8601String(),
          },
        });
        checkActiveSession();
        if (!_isCurrentUser(uid)) return;
        if (me.id.isNotEmpty && me.id != uid) {
          debugPrint('SettingsPrefsSync: 上行响应账号已变化，保留原账号待上行快照');
          continue;
        }
        final stamped = DateTime.tryParse(
          me.settingsPrefs?['syncedAt'] as String? ?? '',
        );
        await saveLastSyncedAt(uid, stamped ?? syncedAt);
        checkActiveSession();
        if (readDirtyPayload(uid) == raw) {
          await saveDirtyPayload(uid, null);
        }
      } on Object catch (e) {
        debugPrint('SettingsPrefsSync: 偏好上行失败（保留快照待重试） $e');
      }
    }
  }

  /// 登录成功 / 启动恢复会话后下行：远端更新才应用，缺键不动。
  Future<void> pull() => _inSession(_pull);

  Future<void> _pull() async {
    checkActiveSession();
    if (!isLoggedIn()) return;
    final uid = userId();
    if (readDirtyPayload(uid) != null) return;
    try {
      final me = await api.getMe();
      checkActiveSession();
      if (!_isCurrentUser(uid) || (me.id.isNotEmpty && me.id != uid)) return;
      if (readDirtyPayload(uid) != null) return;
      final prefs = me.settingsPrefs;
      if (prefs == null || prefs.isEmpty) return;
      final remoteAt = DateTime.tryParse(prefs['syncedAt'] as String? ?? '');
      final localAt = readLastSyncedAt(uid);
      if (localAt != null && (remoteAt == null || !remoteAt.isAfter(localAt))) {
        return;
      }
      _applying = true;
      try {
        applyRemote(prefs);
      } finally {
        _applying = false;
      }
      if (_isCurrentUser(uid)) {
        await saveLastSyncedAt(uid, remoteAt ?? _now().toUtc());
      }
    } on Object catch (e) {
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

/// 偏好同步协调器 Provider：登录/恢复会话调 [SettingsPrefsSync.pull]，
/// RecordSyncEngine 每轮调 [SettingsPrefsSync.flushDirty]；四个偏好变更
/// 先落快照再 push。非 autoDispose，首次读取后常驻。
final settingsPrefsSyncProvider = Provider<SettingsPrefsSync>((ref) {
  final prefs = _tryPrefs(ref);
  final memoryDirty = <String, String>{};
  final memorySyncedAt = <String, DateTime>{};
  final sync = SettingsPrefsSync(
    api: ref.watch(userApiProvider),
    captureSession: () => SessionLease.capture(ref.read(apiDioProvider)),
    isLoggedIn: () {
      try {
        return ref.read(authControllerProvider).status == AuthStatus.loggedIn;
      } on Object {
        return false;
      }
    },
    userId: () {
      try {
        return ref.read(authControllerProvider).userId ?? 'anonymous';
      } on Object {
        return 'anonymous';
      }
    },
    collectLocal: () => _collectLocalPrefs(ref),
    applyRemote: (remote) => _applyRemotePrefs(ref, remote),
    readDirtyPayload: (uid) =>
        prefs?.getString(settingsPrefsDirtyKey(uid)) ?? memoryDirty[uid],
    saveDirtyPayload: (uid, payload) async {
      final store = prefs;
      if (store == null) {
        if (payload == null) {
          memoryDirty.remove(uid);
        } else {
          memoryDirty[uid] = payload;
        }
        return;
      }
      final key = settingsPrefsDirtyKey(uid);
      if (payload == null) {
        await store.remove(key);
      } else {
        await store.setString(key, payload);
      }
    },
    readLastSyncedAt: (uid) {
      final raw = prefs?.getString(lastPrefsSyncedAtKeyFor(uid));
      if (raw != null) return DateTime.tryParse(raw);
      return memorySyncedAt[uid];
    },
    saveLastSyncedAt: (uid, at) async {
      memorySyncedAt[uid] = at;
      await prefs?.setString(
        lastPrefsSyncedAtKeyFor(uid),
        at.toUtc().toIso8601String(),
      );
    },
  );
  ref
    ..listen<String>(languageModeProvider, (_, _) => unawaited(sync.push()))
    ..listen<ThemeMode>(themeModeProvider, (_, _) => unawaited(sync.push()))
    ..listen<WeightUnit>(weightUnitProvider, (_, _) => unawaited(sync.push()))
    ..listen<ExerciseGoals>(
      exerciseGoalsProvider,
      (_, _) => unawaited(sync.push()),
    );
  return sync;
});

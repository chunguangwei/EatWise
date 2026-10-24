import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页应用层：主题/语言偏好（持久化 + 即时生效，D-15/设计稿 §2.7）
/// 与数据导出/账号删除服务（合规 §4.2/§4.3）。

SharedPreferences? _tryPrefs(Ref ref) {
  try {
    return ref.watch(sharedPreferencesProvider);
  } on Object {
    return null; // 未注入场景（测试/预览）不持久化，仅内存生效。
  }
}

/// 主题模式（亮/暗/跟随系统；MaterialApp.themeMode 数据源）。
final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(_tryPrefs(ref)),
);

final class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_load(_prefs));

  static const String _key = 'settings.themeMode';

  final SharedPreferences? _prefs;

  static ThemeMode _load(SharedPreferences? prefs) {
    return switch (prefs?.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// 切换即时生效（全树重建），异步落盘。
  void setMode(ThemeMode mode) {
    state = mode;
    _prefs?.setString(_key, mode.name);
  }
}

/// 语言偏好三态（system / zh-CN / en，规格-i18n §1.1）。
final languageModeProvider =
    StateNotifierProvider<LanguageModeController, String>(
      (ref) => LanguageModeController(_tryPrefs(ref)),
    );

final class LanguageModeController extends StateNotifier<String> {
  LanguageModeController(this._prefs)
    : super(_prefs?.getString(_key) ?? system);

  static const String system = 'system';
  static const String zhCN = 'zh-CN';
  static const String en = 'en';
  static const String _key = 'settings.languageMode';

  final SharedPreferences? _prefs;

  /// 切换即时生效（slang 全树重建），异步落盘。
  void setMode(String mode) {
    state = mode;
    _prefs?.setString(_key, mode);
    applyLocaleMode(mode);
  }

  /// 按三态应用 slang locale（main 启动恢复也走这里）。
  static void applyLocaleMode(String mode) {
    switch (mode) {
      case zhCN:
        LocaleSettings.setLocale(AppLocale.zhCn);
      case en:
        LocaleSettings.setLocale(AppLocale.en);
      default:
        LocaleSettings.useDeviceLocale();
    }
  }
}

/// 启动时恢复语言偏好（main 在 useDeviceLocale 之后调用）。
void restoreLocalePreference(SharedPreferences prefs) {
  final mode = prefs.getString('settings.languageMode');
  if (mode != null) LanguageModeController.applyLocaleMode(mode);
}

/// 端侧小模型估算开关（默认关；开启后自定义食物 AI 估算优先走端侧，
/// 模型未就绪/端侧失败时静默降级 用户 API → 服务端链路）。
final onDeviceAiEnabledProvider =
    StateNotifierProvider<OnDeviceAiEnabledController, bool>(
      (ref) => OnDeviceAiEnabledController(_tryPrefs(ref)),
    );

final class OnDeviceAiEnabledController extends StateNotifier<bool> {
  OnDeviceAiEnabledController(this._prefs)
    : super(_prefs?.getBool(_key) ?? false);

  static const String _key = 'settings.onDeviceAiEnabled';

  final SharedPreferences? _prefs;

  /// 切换即时生效，异步落盘（未注入 prefs 场景仅内存生效）。
  void setEnabled(bool enabled) {
    state = enabled;
    _prefs?.setBool(_key, enabled);
  }
}

/// 数据导出服务（合规 §4.2：查阅复制权，U3 服务端聚合 JSON 直返）。
abstract interface class DataExportService {
  /// 申请导出全量个人数据；返回保存到设备文档目录的文件路径。
  Future<String> requestExport();
}

/// U3 真实导出：POST /users/me/export 聚合 JSON → 写设备文档目录。
/// 写入成功后由设置页调用既有 share_plus 打开系统分享。
final class RemoteDataExportService implements DataExportService {
  RemoteDataExportService(this._api, {Future<Directory> Function()? docsDir})
    : _docsDir = docsDir ?? getApplicationDocumentsDirectory;

  final UserApi _api;
  final Future<Directory> Function() _docsDir;

  @override
  Future<String> requestExport() async {
    final bundle = await _api.exportMe();
    final dir = await _docsDir();
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    final file = File('${dir.path}/eatwise_data_export_$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle),
    );
    return file.path;
  }
}

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return RemoteDataExportService(ref.watch(userApiProvider));
});

/// 账号删除服务（合规 §4.3：冷静期〔假设〕7 天，期内登录自动撤销）。
abstract interface class AccountDeletionService {
  /// 申请删除账号（成功即进入冷静期，服务端吊销全部会话，随后本地登出）。
  Future<AccountDeletionView> requestDeletion();

  /// 冷静期内撤销删除申请（U6，幂等）。
  Future<AccountDeletionView> cancelDeletion();
}

/// U5/U6 真实实现（走 UserApi，错误信封经 ApiException 上抛）。
final class RemoteAccountDeletionService implements AccountDeletionService {
  const RemoteAccountDeletionService(this._api);

  final UserApi _api;

  @override
  Future<AccountDeletionView> requestDeletion() => _api.requestDeletion();

  @override
  Future<AccountDeletionView> cancelDeletion() => _api.cancelDeletion();
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return RemoteAccountDeletionService(ref.watch(userApiProvider));
});

/// 用户端点（U1/U3/U5/U6）。
final userApiProvider = Provider<UserApi>((ref) {
  return UserApi(ref.watch(apiDioProvider));
});

/// 账号标识本地缓存（设置页账号区兜底：U1 失败/离线时仍可显示最近一次
/// 成功拉取的账号标识——username（D-13 v2 主路径）或脱敏手机号；
/// 登出/删除账号时由设置页清除）。缓存按 uid 隔离，旧全局键升级时迁移。
final class AccountIdentityStore {
  AccountIdentityStore(this._prefs, {this.userId = 'anonymous'}) {
    if (userId != 'anonymous' && _prefs.containsKey(key)) {
      if (!_prefs.containsKey(scopedKey)) {
        final legacy = _prefs.getString(key);
        if (legacy != null) _prefs.setString(scopedKey, legacy);
      }
      _prefs.remove(key);
    }
  }

  static const String key = 'settings.cachedMaskedPhone';

  static String keyFor(String userId) => '$key.$userId';

  final String userId;
  final SharedPreferences _prefs;

  String get scopedKey => keyFor(userId);

  String? read() => _prefs.getString(scopedKey);

  Future<void> save(String identity) => _prefs.setString(scopedKey, identity);

  Future<void> clear() async {
    await _prefs.remove(scopedKey);
    await _prefs.remove(key);
  }
}

String _watchAuthUserId(Ref ref) {
  try {
    return ref.watch(authControllerProvider).userId ?? 'anonymous';
  } on Object {
    return 'anonymous';
  }
}

String _readAuthUserId(Ref ref) {
  try {
    return ref.read(authControllerProvider).userId ?? 'anonymous';
  } on Object {
    return 'anonymous';
  }
}

/// SharedPreferences 未注入（测试/预览）时降级 null，缓存链路静默失效。
final accountIdentityStoreProvider = Provider<AccountIdentityStore?>((ref) {
  final userId = _watchAuthUserId(ref);
  final prefs = _tryPrefs(ref);
  return prefs == null ? null : AccountIdentityStore(prefs, userId: userId);
});

/// 当前用户视图（设置页账号区：账号标识 + 删除预约状态）；
/// 未登录/离线/接口失败回落 null（UI 降级显示）。uid 变化会废弃整个视图，
/// 慢响应在写账号缓存或返回前还要再次核对会话，防止 role/avatar 串号。
///
/// 失败自愈：吞错返回 null 会被 Riverpod 当成功值缓存，因此失败时挂 30s
/// 延迟 invalidateSelf；timer 在首个 await 前注册 onDispose，避免泄漏。
final userMeProvider = FutureProvider<UserMeView?>((ref) async {
  final userId = _watchAuthUserId(ref);
  final identityStore = ref.read(accountIdentityStoreProvider);
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
  try {
    final me = await ref.watch(userApiProvider).getMe();
    if (disposed ||
        userId != _readAuthUserId(ref) ||
        (userId != 'anonymous' && me.id != userId)) {
      return null;
    }
    final identity = me.username.isNotEmpty ? me.username : me.maskedPhone;
    if (identity.isNotEmpty) await identityStore?.save(identity);
    return me;
  } on Object {
    if (!disposed) {
      timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    }
    return null;
  }
});

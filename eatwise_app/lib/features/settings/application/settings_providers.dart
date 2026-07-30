import 'dart:convert';
import 'dart:io';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/network_providers.dart';
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

/// 数据导出服务（合规 §4.2：查阅复制权，U3 服务端聚合 JSON 直返）。
abstract interface class DataExportService {
  /// 申请导出全量个人数据；返回保存到设备文档目录的文件路径。
  Future<String> requestExport();
}

/// U3 真实导出：POST /users/me/export 聚合 JSON → 写设备文档目录
/// （path_provider 既有依赖，不引入分享插件〔最简可靠方案〕）。
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

/// 当前用户视图（设置页账号区：脱敏手机号 + 删除预约状态）；
/// 未登录/离线/接口失败回落 null（UI 降级显示）。
final userMeProvider = FutureProvider<UserMeView?>((ref) async {
  try {
    return await ref.watch(userApiProvider).getMe();
  } on Object {
    return null;
  }
});

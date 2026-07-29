import 'dart:convert';
import 'dart:io';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
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

/// 数据导出服务（合规 §4.2：查阅复制权，JSON+CSV 服务端异步生成）。
abstract interface class DataExportService {
  /// 申请导出全量个人数据；返回交付描述（stub 为本地占位文件路径）。
  Future<String> requestExport();
}

/// 〔stub〕服务端 U3/U4（POST /users/me/export / 查询任务）尚未实现：
/// 客户端生成含授权状态的本地 JSON 占位文件并标注；端点上线后切换为
/// 服务端异步任务流（生成完成 App 内通知 + 72h 下载链接）。
final class LocalStubDataExportService implements DataExportService {
  factory LocalStubDataExportService({
    required PrivacyConsentStore consentStore,
  }) => LocalStubDataExportService._(consentStore);

  LocalStubDataExportService._(this._consentStore);

  final PrivacyConsentStore _consentStore;

  @override
  Future<String> requestExport() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/eatwise_data_export_stub.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'stub': true,
        'note': '服务端导出端点 U3/U4 未实现，本文件为客户端占位（合规 §4.2）',
        'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'policyVersion': PrivacyConsentStore.currentPolicyVersion,
        'healthDataGranted': _consentStore.healthDataGranted,
        'consentAgreedAtEpochSec': _consentStore.agreedAtEpochSec,
      }),
    );
    return file.path;
  }
}

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return LocalStubDataExportService(
    consentStore: ref.watch(privacyConsentStoreProvider),
  );
});

/// 账号删除服务（合规 §4.3：7 天冷静期〔假设〕，冷静期内登录即撤销）。
abstract interface class AccountDeletionService {
  /// 申请删除账号（成功即进入冷静期，随后本地登出冻结）。
  Future<void> requestDeletion();
}

/// 〔stub〕服务端 U5（POST /users/me/deletion）尚未实现：空实现直接返回
/// 成功并标注；冷静期冻结、第 7 天物理删除与本地库清除由服务端/同步层
/// 实现后接管。
final class StubAccountDeletionService implements AccountDeletionService {
  const StubAccountDeletionService();

  @override
  Future<void> requestDeletion() async {}
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return const StubAccountDeletionService();
});

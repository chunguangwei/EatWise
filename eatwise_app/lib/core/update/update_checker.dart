import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/version_compare.dart';

/// 更新检查器：调服务端 `/app/version/latest`（服务端代理 GitHub Releases，
/// 私有仓库故 App 不持 token），与当前版本比较得出三态。
///
/// 平台门（产品决策 2026-09-18）：iOS 不提示更新——App 未上架 App Store，
/// 「去下载 APK」式提醒在 iOS 无意义（服务端对 iOS 的 apkUrl 恒为 null），
/// 故 iOS 不发请求直接报「已是最新」，启动静默检查与设置页手动检查
/// 两条链路因此都不弹窗；上架 App Store 后移除此门、改为跳 App Store。
///
/// `currentVersion` 默认由 package_info_plus 注入（见 update_providers），
/// 测试可注入固定值；`platform` 默认按 Platform.isAndroid/IOS 判定。
final class UpdateChecker {
  UpdateChecker({
    required this._dio,
    required this._currentVersion,
    String? platform,
  }) : _platform =
           platform ??
           (Platform.isAndroid
               ? 'android'
               : Platform.isIOS
               ? 'ios'
               : 'android');

  final Dio _dio;
  final Future<String> Function() _currentVersion;
  final String _platform;

  /// iOS 平台门的占位结果（仅 status 被消费；upToDate 不触发弹窗，
  /// 设置页手动检查据此提示「已是最新」）。
  static const AppVersionInfo _iosSuppressedInfo = AppVersionInfo(
    latestVersion: '',
    minSupportedVersion: '1.0.0',
    releaseNotesZh: '',
    releaseNotesEn: '',
    apkUrl: null,
    publishedAt: null,
    source: 'suppressed',
  );

  /// 执行一次检查。网络/服务端异常向上抛出（调用方决定静默或提示）。
  /// iOS 命中平台门：不发请求，直接返回「已是最新」占位结果。
  Future<UpdateCheckResult> check() async {
    if (_platform == 'ios') {
      return const UpdateCheckResult(
        status: UpdateStatus.upToDate,
        info: _iosSuppressedInfo,
      );
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/app/version/latest',
      queryParameters: <String, String>{'platform': _platform},
    );
    final info = AppVersionInfo.fromJson(response.data ?? const {});
    final current = await _currentVersion();
    final status = _decide(current, info);
    return UpdateCheckResult(status: status, info: info);
  }

  /// 三态判定（纯函数，便于边界测试）：
  /// 当前 < minSupportedVersion → 强制；当前 < latestVersion → 可选；否则最新。
  static UpdateStatus decide(String currentVersion, AppVersionInfo info) =>
      _decide(currentVersion, info);

  static UpdateStatus _decide(String currentVersion, AppVersionInfo info) {
    if (compareAppVersions(currentVersion, info.minSupportedVersion) < 0) {
      return UpdateStatus.forced;
    }
    if (compareAppVersions(currentVersion, info.latestVersion) < 0) {
      return UpdateStatus.available;
    }
    return UpdateStatus.upToDate;
  }
}

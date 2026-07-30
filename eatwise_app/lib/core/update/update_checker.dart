import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/version_compare.dart';

/// 更新检查器：调服务端 `/app/version/latest`（服务端代理 GitHub Releases，
/// 私有仓库故 App 不持 token），与当前版本比较得出三态。
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

  /// 执行一次检查。网络/服务端异常向上抛出（调用方决定静默或提示）。
  Future<UpdateCheckResult> check() async {
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

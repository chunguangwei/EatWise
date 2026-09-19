import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/version_compare.dart';

/// 更新检查器：直连 GitHub `releases/latest`（2026-09-19 起仓库 public，
/// 匿名可读 60 次/小时/IP，启动检查有 ≥24h 节流兜底），与当前版本比较
/// 得出三态。**注意注入的 dio 必须是裸实例**（不带服务端 baseUrl/信封
/// 拦截器，见 update_providers）。
///
/// 平台门（产品决策 2026-09-18）：iOS 不提示更新——App 未上架 App Store，
/// 「去下载 APK」式提醒在 iOS 无意义，故 iOS 不发请求直接报「已是最新」；
/// 上架 App Store 后移除此门、改为跳 App Store。
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

  /// GitHub 最新 release 端点（公开仓，匿名 GET）。
  static const String latestReleaseUrl =
      'https://api.github.com/repos/chunguangwei/EatWise/releases/latest';

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

  /// 执行一次检查。网络/GitHub 异常向上抛出（调用方决定静默或提示）。
  /// iOS 命中平台门：不发请求，直接返回「已是最新」占位结果。
  Future<UpdateCheckResult> check() async {
    if (_platform == 'ios') {
      return const UpdateCheckResult(
        status: UpdateStatus.upToDate,
        info: _iosSuppressedInfo,
      );
    }
    final response = await _dio.get<Map<String, dynamic>>(
      latestReleaseUrl,
      options: Options(
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'eatwise-app',
        },
      ),
    );
    final info = AppVersionInfo.fromGitHubRelease(response.data ?? const {});
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

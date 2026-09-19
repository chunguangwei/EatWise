/// 应用内更新检查的数据模型（对应服务端 GET /v1/app/version/latest）。
library;

/// 服务端返回的最新版本信息。
final class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.releaseNotesZh,
    required this.releaseNotesEn,
    required this.apkUrl,
    this.apkUrlFallback,
    required this.publishedAt,
    required this.source,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    final notes = json['releaseNotes'];
    final notesMap = notes is Map<String, dynamic>
        ? notes
        : const <String, dynamic>{};
    return AppVersionInfo(
      latestVersion: json['latestVersion'] as String? ?? '',
      minSupportedVersion: json['minSupportedVersion'] as String? ?? '1.0.0',
      releaseNotesZh: notesMap['zh'] as String? ?? '',
      releaseNotesEn: notesMap['en'] as String? ?? '',
      apkUrl: json['apkUrl'] as String?,
      apkUrlFallback: json['apkUrlFallback'] as String?,
      publishedAt: json['publishedAt'] as String?,
      source: json['source'] as String? ?? 'github',
    );
  }

  /// 自托管兜底下载地址（VPS apk-sync 托管的最新包）。更新检测直连
  /// GitHub 后不经服务端下发，兜底地址为客户端常量。
  static const String selfHostedApkFallbackUrl =
      'https://wcg.polin.tech:8443/downloads/eatwise-latest.apk';

  /// 从 GitHub `releases/latest` 原始 JSON 解析（2026-09-19 起更新检测
  /// 直连 GitHub：仓库 public 匿名可读，不再经服务端代理；下载仍走
  /// 端内 UpdateDownloader，主链 GitHub CDN + 自托管兜底续传）。
  /// Release body 单语 zh/en 同填；最低支持版本无下发渠道，常量 1.0.0
  /// 兜底（强制更新阈值〔假设〕）。
  factory AppVersionInfo.fromGitHubRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    String? apkUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic> &&
            (asset['name'] as String? ?? '').endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
    }
    return AppVersionInfo(
      latestVersion: tag.replaceFirst(RegExp('^v', caseSensitive: false), ''),
      minSupportedVersion: '1.0.0',
      releaseNotesZh: body,
      releaseNotesEn: body,
      apkUrl: apkUrl,
      apkUrlFallback: selfHostedApkFallbackUrl,
      publishedAt: json['published_at'] as String?,
      source: 'github',
    );
  }

  final String latestVersion;
  final String minSupportedVersion;
  final String releaseNotesZh;
  final String releaseNotesEn;

  /// Android APK 下载主链（GitHub release asset，CDN）；iOS 为 null（走 App Store 占位〔假设〕）。
  final String? apkUrl;

  /// Android APK 兜底下载地址（自托管，主链连续失败时切换）；未配为 null。
  final String? apkUrlFallback;
  final String? publishedAt;

  /// 数据来源：github / fallback（env 兜底）。
  final String source;

  /// 按语言取 release notes（zh 之外一律 en）。
  String releaseNotesFor(String languageTag) =>
      languageTag.startsWith('zh') ? releaseNotesZh : releaseNotesEn;
}

/// 更新检查三态。
enum UpdateStatus {
  /// 已是最新。
  upToDate,

  /// 有可选更新。
  available,

  /// 强制更新（当前版本 < minSupportedVersion）。
  forced,
}

/// 一次检查的结果。
final class UpdateCheckResult {
  const UpdateCheckResult({required this.status, required this.info});

  final UpdateStatus status;
  final AppVersionInfo info;
}

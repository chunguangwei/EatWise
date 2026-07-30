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
      publishedAt: json['publishedAt'] as String?,
      source: json['source'] as String? ?? 'github',
    );
  }

  final String latestVersion;
  final String minSupportedVersion;
  final String releaseNotesZh;
  final String releaseNotesEn;

  /// Android APK 下载地址；iOS 为 null（走 App Store 占位〔假设〕）。
  final String? apkUrl;
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

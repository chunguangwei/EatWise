import 'package:eatwise/core/update/update_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// 「立即更新」跳转：Android 外部浏览器打开 APK 下载地址；
/// iOS 打开 App Store 页（URL 占位〔假设〕，待上架后替换真实 App ID）。
/// 当前 iOS 在 UpdateChecker 平台门处即不提示更新，本跳转实际仅 Android 可达。
final class UpdateLauncher {
  const UpdateLauncher({Future<bool> Function(Uri url)? launch})
    : _launch = launch ?? _defaultLaunch;

  /// iOS App Store 页占位〔假设〕（未上架，上架后替换真实链接）。
  static const String iosAppStoreUrl =
      'https://apps.apple.com/app/id0000000000';

  final Future<bool> Function(Uri url) _launch;

  static Future<bool> _defaultLaunch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// 打开更新入口；地址缺失或跳转失败返回 false（调用方提示）。
  Future<bool> openUpdate(AppVersionInfo info, {required String platform}) {
    final url = platform == 'ios' ? iosAppStoreUrl : info.apkUrl;
    if (url == null || url.isEmpty) return Future<bool>.value(false);
    return _launch(Uri.parse(url));
  }
}

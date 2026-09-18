import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// 下载进度回调：received 已收字节，total 总字节（服务端未给长度时为 -1）。
typedef UpdateProgressCallback = void Function(int received, int total);

/// 打开已下载 APK（调起系统安装器）的抽象，测试注入假实现。
typedef ApkFileOpener = Future<bool> Function(String path);

/// 应用内 APK 下载器（D-15 后续）：自托管 apkUrl 为自签名证书
/// （https://wcg.polin.tech:8443），浏览器直开会弹证书警告，故改为 App 内
/// 用带证书锁定的 dio（装配见 update_providers.dart，与 analytics 裸 Dio
/// 同口径）流式下载到临时目录，完成后经 open_filex 调起系统安装器
/// （Android 触发「允许安装未知来源应用」流程，需 REQUEST_INSTALL_PACKAGES）。
final class UpdateDownloader {
  UpdateDownloader({
    required this._dio,
    ApkFileOpener? openApk,
    Future<Directory> Function()? tempDir,
  }) : _openApk = openApk ?? _defaultOpenApk,
       _tempDir = tempDir ?? getTemporaryDirectory;

  /// 临时目录下的固定文件名（重复下载直接覆盖，不留孤儿分片）。
  static const String apkFileName = 'eatwise-update.apk';

  final Dio _dio;
  final ApkFileOpener _openApk;
  final Future<Directory> Function() _tempDir;

  static Future<bool> _defaultOpenApk(String path) async {
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }

  /// 流式下载 APK 到临时目录并调起系统安装器。任一步失败返回 false
  /// （调用方给重试入口）；成功以安装器是否成功调起为准。
  Future<bool> downloadAndInstall(
    String apkUrl, {
    UpdateProgressCallback? onProgress,
  }) async {
    try {
      final dir = await _tempDir();
      final savePath = '${dir.path}${Platform.pathSeparator}$apkFileName';
      await _dio.download(apkUrl, savePath, onReceiveProgress: onProgress);
      return await _openApk(savePath);
    } on Object {
      return false;
    }
  }
}

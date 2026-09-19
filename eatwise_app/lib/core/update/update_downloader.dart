import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 下载进度回调：received 已收字节（跨续传/重试累计，不回退），
/// total 总字节（服务端未给长度时为 -1）。
typedef UpdateProgressCallback = void Function(int received, int total);

/// 打开已下载 APK（调起系统安装器）的抽象，测试注入假实现。
typedef ApkFileOpener = Future<bool> Function(String path);

/// 屏幕常亮开关的抽象（默认 wakelock_plus），测试注入假实现。
typedef WakelockAction = Future<void> Function();

/// Content-Range 头（`bytes 100-999/2000`，416 时为 `bytes */2000`）
/// 解析总字节数（纯函数）；缺失/非法返回 null。
int? parseContentRangeTotal(String? contentRange) {
  if (contentRange == null) return null;
  final slash = contentRange.lastIndexOf('/');
  if (slash < 0) return null;
  return int.tryParse(contentRange.substring(slash + 1).trim());
}

/// 应用内 APK 下载器（2026-09-19 分发链路调整）：主链为 GitHub release
/// asset（CDN），apkUrlFallback 为自托管兜底（小带宽 VPS）。
///
/// 下载策略：
/// - **断点续传**：先写 `eatwise-update.apk.part`，完成才 rename；.part 已存在
///   则带 `Range: bytes=<已收>-` 请求，206 追加写、200（服务端不认 Range）
///   截断重下、416 视为已完整（交给大小校验）。GitHub asset 会 302 到
///   objects.githubusercontent.com，每次重试重新发请求让 Dio 重走重定向；
/// - **失败重试**：连接中断/超时/非 2xx 自动重试（每 URL 最多
///   [maxAttemptsPerUrl] 次，指数退避 1s/2s…），主链耗尽切兜底 URL
///   （.part 续传跨 URL 成立——同一文件；总长度不一致则清 .part 重下）；
/// - **保活**：下载期间 wakelock 保持屏幕常亮，结束（成功/失败）必释放；
/// - **完整性**：完成后校验文件大小 == 服务端声明总字节（有 Content-Length/
///   Content-Range 时），不符保留 .part 供重试续传。
final class UpdateDownloader {
  UpdateDownloader({
    required this._dio,
    ApkFileOpener? openApk,
    Future<Directory> Function()? tempDir,
    WakelockAction? acquireWakelock,
    WakelockAction? releaseWakelock,
    Future<void> Function(Duration)? sleep,
    this.maxAttemptsPerUrl = 3,
  }) : _openApk = openApk ?? _defaultOpenApk,
       _tempDir = tempDir ?? getTemporaryDirectory,
       _acquireWakelock = acquireWakelock ?? WakelockPlus.enable,
       _releaseWakelock = releaseWakelock ?? WakelockPlus.disable,
       _sleep = sleep ?? Future<void>.delayed;

  /// 临时目录下的最终文件名（.part 完成后 rename 至此，重复下载覆盖）。
  static const String apkFileName = 'eatwise-update.apk';

  /// 续传分片后缀（下载中的不完整文件）。
  static const String partFileSuffix = '.part';

  /// 每个 URL 的最大尝试次数（首次 + 重试）。
  final int maxAttemptsPerUrl;

  final Dio _dio;
  final ApkFileOpener _openApk;
  final Future<Directory> Function() _tempDir;
  final WakelockAction _acquireWakelock;
  final WakelockAction _releaseWakelock;
  final Future<void> Function(Duration) _sleep;

  static Future<bool> _defaultOpenApk(String path) async {
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }

  /// 下载 APK（主链 [apkUrl]，连续失败切 [fallbackUrl]）并调起系统安装器。
  /// 任一步最终失败返回 false（调用方给重试入口，.part 保留可续传）；
  /// 成功以安装器是否成功调起为准。
  Future<bool> downloadAndInstall(
    String apkUrl, {
    String? fallbackUrl,
    UpdateProgressCallback? onProgress,
  }) async {
    await _acquireWakelock();
    try {
      final dir = await _tempDir();
      final finalPath = '${dir.path}${Platform.pathSeparator}$apkFileName';
      final ok = await _downloadWithResume(
        apkUrl,
        fallbackUrl,
        '$finalPath$partFileSuffix',
        finalPath,
        onProgress,
      );
      if (!ok) return false;
      return await _openApk(finalPath);
    } on Object {
      return false;
    } finally {
      await _releaseWakelock();
    }
  }

  /// 主链 → 兜底依次尝试，每个 URL 指数退避重试；成功返回 true。
  Future<bool> _downloadWithResume(
    String primaryUrl,
    String? fallbackUrl,
    String partPath,
    String finalPath,
    UpdateProgressCallback? onProgress,
  ) async {
    final urls = <String>[
      primaryUrl,
      if (fallbackUrl != null && fallbackUrl.isNotEmpty) fallbackUrl,
    ];
    final partFile = File(partPath);
    // 首个成功响应声明的总字节：换 URL 时据此校验 .part 是否同一文件。
    var expectedTotal = -1;
    for (final url in urls) {
      for (var attempt = 0; attempt < maxAttemptsPerUrl; attempt++) {
        if (attempt > 0) {
          // 指数退避：1s / 2s / 4s…
          await _sleep(Duration(seconds: 1 << (attempt - 1)));
        }
        final int total;
        try {
          total = await _fetchToFile(url, partFile, onProgress);
        } on Object {
          continue; // 连接中断/超时/非 2xx：退避后重试（.part 续传）
        }
        if (expectedTotal > 0 && total > 0 && total != expectedTotal) {
          // 换 URL 后总长度不一致：.part 内容非同一文件，清除后本轮按不完整
          // 处理，下一 attempt 从 0 重下。
          if (await partFile.exists()) await partFile.delete();
        }
        if (total > 0) expectedTotal = total;
        final downloaded = await partFile.exists()
            ? await partFile.length()
            : 0;
        if (total > 0 && downloaded != total) {
          continue; // 不完整：保留 .part，下一 attempt 带 Range 续传
        }
        await partFile.rename(finalPath);
        return true;
      }
    }
    return false;
  }

  /// 单次请求：带 Range 续传，返回服务端声明的总字节数（未知 -1）。
  /// 206 追加写、200（不认 Range）截断重下、416（Range 越界，.part 已完整）
  /// 不写数据仅取总字节；其余状态码抛出让上层重试/切兜底。
  Future<int> _fetchToFile(
    String url,
    File partFile,
    UpdateProgressCallback? onProgress,
  ) async {
    final resumeFrom = await partFile.exists() ? await partFile.length() : 0;
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: resumeFrom > 0
            ? <String, String>{'range': 'bytes=$resumeFrom-'}
            : null,
        // 状态码全部放行，下面显式判定（4xx/5xx 走重试逻辑）。
        validateStatus: (_) => true,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 416) {
      return parseContentRangeTotal(response.headers.value('content-range')) ??
          -1;
    }
    if (status != 200 && status != 206) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    final body = response.data;
    if (body == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    final resumed = status == 206 && resumeFrom > 0;
    // 206 的总字节以 Content-Range 为准；200 为 content-length。
    final total = resumed
        ? (parseContentRangeTotal(response.headers.value('content-range')) ??
              -1)
        : (int.tryParse(
                response.headers.value(Headers.contentLengthHeader) ?? '',
              ) ??
              -1);
    final sink = partFile.openWrite(
      mode: resumed ? FileMode.writeOnlyAppend : FileMode.write,
    );
    // 进度累计：续传从已收字节继续，不回退；200 重下从 0 计。
    var received = resumed ? resumeFrom : 0;
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return total;
  }
}

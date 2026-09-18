/// 端侧模型下载管理器：双源选源 + Range 断点续传 + 双校验 + 原子落盘。
///
/// 链路设计照 imagepilot `classifierModelSource.ensureLargeModel` 平移：
/// - 按系统 locale 选源（zh* → ModelScope 优先，其余 → GitHub 优先），一源失败自动换源；
/// - `.part` 临时文件保留已下字节，续传时剩余段下到 `.tail`（`Range: bytes=N-`），
///   服务器回 206 → 追加合并，回 200（忽略 Range）→ 整包替换，416（Range 越界）
///   且 `.part` 已达标 → 直接转正；
/// - 完成时「字节数 + LITERTLM 魔数」双校验（防下到 HTML 错误页「大小够就放行」
///   后端侧加载才崩）；
/// - 全部通过后原子 rename 落盘到 应用文档目录/models/。
///
/// 不直接用 flutter_gemma 的 fromNetwork 下载：其失败重试不续传且残留孤儿分片
/// （spike 实测残留 ~2GB），也无魔数校验（spike §7-5）。
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_spec.dart';
import 'package:path_provider/path_provider.dart';

// ==================== 异常（typed error，上层按类型决策） ====================

sealed class OnDeviceModelException implements Exception {
  const OnDeviceModelException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 可用存储不足（下载前预检拦截）。
final class OnDeviceInsufficientStorageException
    extends OnDeviceModelException {
  const OnDeviceInsufficientStorageException({
    required this.requiredBytes,
    required this.freeBytes,
  }) : super('可用存储不足：需要 $requiredBytes 字节，仅剩 $freeBytes 字节');

  final int requiredBytes;
  final int freeBytes;
}

/// 物理内存低于门槛（低端机放行会在加载途中被系统 OOM-kill）。
final class OnDeviceInsufficientMemoryException extends OnDeviceModelException {
  const OnDeviceInsufficientMemoryException({
    required this.requiredMB,
    required this.actualMB,
  }) : super('物理内存不足：需要 ${requiredMB}MB，实际 ${actualMB}MB');

  final int requiredMB;
  final int actualMB;
}

/// 单源下载失败（HTTP 错误/网络异常）；所有源失败时抛最后一个。
final class OnDeviceDownloadException extends OnDeviceModelException {
  const OnDeviceDownloadException(super.message, {this.statusCode});

  final int? statusCode;
}

/// 完整性校验失败（字节数不够或魔数不对，可能下到错误页/文件损坏）。
final class OnDeviceCorruptModelException extends OnDeviceModelException {
  const OnDeviceCorruptModelException(super.message);
}

/// 用户取消（`.part` 已保留，可断点续传）。
final class OnDeviceDownloadCancelledException extends OnDeviceModelException {
  const OnDeviceDownloadCancelledException() : super('下载已取消');
}

// ==================== 取消令牌 ====================

/// 下载取消令牌（与 Dio CancelToken 解耦，测试可用纯 Dart 实现）。
final class ModelDownloadCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

// ==================== HTTP 抽象（测试注入 Fake） ====================

/// 大文件下载能力抽象（单测注入 Fake 验证 Range 头/换源/取消，
/// 生产用 [DioModelHttpClient]）。
abstract interface class ModelHttpClient {
  /// 把 [url] 下载到 [savePath]，返回 HTTP 状态码。
  /// [rangeHeader] 形如 `bytes=12345-`（续传）；进度回调收到本段已收/总字节。
  /// 取消时必须抛 [OnDeviceDownloadCancelledException]。
  Future<int> downloadToFile(
    String url,
    String savePath, {
    String? rangeHeader,
    void Function(int received, int total)? onProgress,
    ModelDownloadCancelToken? cancelToken,
  });
}

/// Dio 实现（不复用 apiDioProvider——那是面向服务端信封/鉴权的装配；
/// 模型 CDN 直连用裸 Dio，大文件流式落盘）。
final class DioModelHttpClient implements ModelHttpClient {
  DioModelHttpClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 大文件下载放宽接收超时（连接 30s；接收 10 分钟无数据才判死）。
  static const Duration _connectTimeout = Duration(seconds: 30);
  static const Duration _receiveTimeout = Duration(minutes: 10);

  @override
  Future<int> downloadToFile(
    String url,
    String savePath, {
    String? rangeHeader,
    void Function(int received, int total)? onProgress,
    ModelDownloadCancelToken? cancelToken,
  }) async {
    final dioToken = CancelToken();
    void bridge() => dioToken.cancel();
    cancelToken?.addListener(bridge);
    try {
      if (cancelToken?.isCancelled ?? false) {
        throw const OnDeviceDownloadCancelledException();
      }
      final response = await _dio.download(
        url,
        savePath,
        // 取消/出错不得删半成品：.part 已下字节是断点续传的全部依据
        //（dio 默认 deleteOnError:true，取消时会把 .part 物理删除，
        // 导致 Resume 从 0% 重下）。
        deleteOnError: false,
        options: Options(
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          // 续传时才带 Range（不带 headers 键与全新下载行为一致）；
          // 4xx/5xx 也要拿到状态码做 416 容错与换源决策，不直接抛。
          headers: rangeHeader != null ? {'Range': rangeHeader} : null,
          validateStatus: (_) => true,
        ),
        cancelToken: dioToken,
        onReceiveProgress: onProgress,
      );
      return response.statusCode ?? 0;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel ||
          (cancelToken?.isCancelled ?? false)) {
        throw const OnDeviceDownloadCancelledException();
      }
      throw OnDeviceDownloadException('网络异常：${e.message ?? e}');
    } finally {
      cancelToken?.removeListener(bridge);
    }
  }
}

// ==================== 设备能力探测 ====================

/// 下载前门槛检查（可用存储 / 物理内存）。返回 null 表示「未知 → 放行」。
abstract interface class DeviceCapabilityProbe {
  /// [path] 所在分区的可用字节数；无法获取返回 null。
  Future<int?> freeStorageBytes(String path);

  /// 设备物理内存（MB）；无法获取返回 null。
  Future<int?> physicalMemoryMB();
}

/// 默认实现：全部放行。
///
/// Flutter 生态暂无项目内可用的「物理内存/剩余磁盘」插件（imagepilot 走 RN
/// 原生模块 RNFS.sysinfo）。后续接入原生 channel 或插件时实现本接口并经
/// provider 覆盖注入即可；放行兜底的安全性由两道防线补足——
/// 存储：下载失败/校验失败会进 error 态；内存：引擎加载 OOM 由网关层
/// typed error 上报，上层永久禁用并降级。
final class PermissiveDeviceCapabilityProbe implements DeviceCapabilityProbe {
  const PermissiveDeviceCapabilityProbe();

  @override
  Future<int?> freeStorageBytes(String path) async => null;

  @override
  Future<int?> physicalMemoryMB() async => null;
}

// ==================== 状态机 ====================

enum OnDeviceModelStatus {
  /// 未下载（或刚删除）。
  notDownloaded,

  /// 下载中（含换源重试）。
  downloading,

  /// 已暂停（用户取消；`.part` 保留，ensureModel 再调即续传）。
  paused,

  /// 模型就绪（字节数 + 魔数双校验通过）。
  ready,

  /// 失败（所有源均失败/校验不过/门槛拦截）。
  error,
}

/// 管理器对外状态快照（UI 进度条数据源）。
final class OnDeviceModelSnapshot {
  const OnDeviceModelSnapshot({
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes = OnDeviceModelSpec.expectedBytes,
    this.error,
  });

  final OnDeviceModelStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final OnDeviceModelException? error;

  /// 0~1 下载进度；总量未知时返回 null。
  double? get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : null;

  @override
  String toString() =>
      'OnDeviceModelSnapshot($status, $downloadedBytes/$totalBytes, $error)';
}

// ==================== 管理器 ====================

final class OnDeviceModelManager {
  OnDeviceModelManager({
    ModelHttpClient? http,
    Future<Directory> Function()? docsDir,
    DeviceCapabilityProbe? capability,
    String Function()? deviceLocale,
    String Function()? operatingSystem,
    int? expectedBytes,
  }) : _http = http ?? DioModelHttpClient(),
       _docsDir = docsDir ?? getApplicationDocumentsDirectory,
       _capability = capability ?? const PermissiveDeviceCapabilityProbe(),
       _deviceLocale = deviceLocale ?? (() => Platform.localeName),
       _operatingSystem = operatingSystem ?? (() => Platform.operatingSystem),
       _expectedBytes = expectedBytes ?? OnDeviceModelSpec.expectedBytes;

  final ModelHttpClient _http;
  final Future<Directory> Function() _docsDir;
  final DeviceCapabilityProbe _capability;
  final String Function() _deviceLocale;
  final String Function() _operatingSystem;

  /// 完整性校验字节数（生产 = [OnDeviceModelSpec.expectedBytes]；
  /// 单测注入小值，避免真的写 2.4GB 文件）。
  final int _expectedBytes;

  final _controller = StreamController<OnDeviceModelSnapshot>.broadcast();
  OnDeviceModelSnapshot _snapshot = const OnDeviceModelSnapshot(
    status: OnDeviceModelStatus.notDownloaded,
  );

  ModelDownloadCancelToken? _activeToken;
  Future<String>? _running;

  /// 当前状态快照。
  OnDeviceModelSnapshot get snapshot => _snapshot;

  /// 状态流（broadcast，riverpod StreamProvider 直接接）。
  Stream<OnDeviceModelSnapshot> get snapshots => _controller.stream;

  void _emit(OnDeviceModelSnapshot next) {
    _snapshot = next;
    _controller.add(next);
  }

  /// error 快照（带 .part 实际进度）：失败时进度条不归零——已下载比例
  /// 保留，UI 据此提示「重试将从断点继续」（观感上证明断点续传存在）。
  Future<OnDeviceModelSnapshot> _errorSnap(OnDeviceModelException e) async {
    final downloaded = await _fileSize(await _partFile());
    return _snap(
      OnDeviceModelStatus.error,
      downloadedBytes: downloaded,
      error: e,
    );
  }

  /// 构造快照（总量统一取 [_expectedBytes]，测试注入小值时进度百分比仍正确）。
  OnDeviceModelSnapshot _snap(
    OnDeviceModelStatus status, {
    int downloadedBytes = 0,
    OnDeviceModelException? error,
  }) => OnDeviceModelSnapshot(
    status: status,
    downloadedBytes: downloadedBytes,
    totalBytes: _expectedBytes,
    error: error,
  );

  Future<Directory> _modelsDir() async {
    final docs = await _docsDir();
    return Directory('${docs.path}/${OnDeviceModelSpec.modelsDirName}');
  }

  /// 模型最终落盘路径（不检查存在性；引擎网关 load 用）。
  Future<String> modelPath() async =>
      '${(await _modelsDir()).path}/${OnDeviceModelSpec.fileName}';

  Future<File> _partFile() async => File('${await modelPath()}.part');

  Future<File> _tailFile() async => File('${await modelPath()}.tail');

  Future<int> _fileSize(File f) async =>
      await f.exists() ? await f.length() : 0;

  /// 魔数校验：文件头必须精确等于 `LITERTLM`（防 HTML 错误页/文件头损坏）。
  Future<bool> _hasValidMagic(File f) async {
    const magic = OnDeviceModelSpec.magicBytes;
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      final head = await raf.read(magic.length);
      if (head.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) return false;
      }
      return true;
    } on Object {
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// 模型是否就绪（存在 + 字节数达标 + 魔数正确）。
  Future<bool> isReady() async {
    final f = File(await modelPath());
    if (!await f.exists()) return false;
    if (await f.length() < _expectedBytes) return false;
    return _hasValidMagic(f);
  }

  /// 按磁盘实况刷新状态（启动时调用一次，校正 ready/notDownloaded）。
  Future<void> refresh() async {
    if (_snapshot.status == OnDeviceModelStatus.downloading) return;
    final ready = await isReady();
    // 磁盘有 .part 残留说明上次下到一半（被杀进程），呈 paused 可续传。
    final partSize = await _partFile().then(_fileSize);
    _emit(
      _snap(
        ready
            ? OnDeviceModelStatus.ready
            : partSize > 0
            ? OnDeviceModelStatus.paused
            : OnDeviceModelStatus.notDownloaded,
        downloadedBytes: ready ? _expectedBytes : partSize,
      ),
    );
  }

  /// 确保模型就绪：已就绪直接返回路径，否则（续传）下载。并发调用共享同一下载。
  /// 失败抛 [OnDeviceModelException] 子类；取消抛 [OnDeviceDownloadCancelledException]。
  Future<String> ensureModel() {
    final running = _running;
    if (running != null) return running;
    final future = _ensureModelInternal().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  /// 取消进行中的下载 → 状态转 paused（`.part` 保留，可续传）。
  void cancel() => _activeToken?.cancel();

  /// 删除模型与全部临时文件（设置页「释放空间」入口）。
  Future<void> delete() async {
    cancel();
    for (final f in [
      File(await modelPath()),
      await _partFile(),
      await _tailFile(),
    ]) {
      if (await f.exists()) await f.delete();
    }
    _emit(_snap(OnDeviceModelStatus.notDownloaded));
  }

  Future<String> _ensureModelInternal() async {
    final dest = File(await modelPath());
    if (await isReady()) {
      _emit(_snap(OnDeviceModelStatus.ready, downloadedBytes: _expectedBytes));
      return dest.path;
    }

    // ---- 门槛检查（探测返回 null = 未知 → 放行） ----
    final memMB = await _capability.physicalMemoryMB();
    final requiredMB = minDeviceMemMBForPlatform(_operatingSystem());
    if (memMB != null && memMB < requiredMB) {
      final e = OnDeviceInsufficientMemoryException(
        requiredMB: requiredMB,
        actualMB: memMB,
      );
      _emit(await _errorSnap(e));
      throw e;
    }
    final dir = await _modelsDir();
    await dir.create(recursive: true);
    final freeBytes = await _capability.freeStorageBytes(dir.path);
    final required = OnDeviceModelSpec.requiredFreeStorageBytes;
    if (freeBytes != null && freeBytes < required) {
      final e = OnDeviceInsufficientStorageException(
        requiredBytes: required,
        freeBytes: freeBytes,
      );
      _emit(await _errorSnap(e));
      throw e;
    }

    final token = ModelDownloadCancelToken();
    _activeToken = token;
    try {
      final candidates = onDeviceModelUrlCandidates(
        preferChina: prefersChinaModelSource(_deviceLocale()),
      );
      OnDeviceModelException? lastError;

      for (final url in candidates) {
        if (token.isCancelled) break;
        try {
          final path = await _downloadFromSource(url, dest, token);
          _emit(
            _snap(OnDeviceModelStatus.ready, downloadedBytes: _expectedBytes),
          );
          return path;
        } on OnDeviceDownloadCancelledException {
          rethrow;
        } on OnDeviceModelException catch (e) {
          lastError = e; // 换源重试
        }
      }
      if (token.isCancelled) throw const OnDeviceDownloadCancelledException();
      final error = lastError ?? const OnDeviceDownloadException('所有下载源均失败');
      _emit(await _errorSnap(error));
      throw error;
    } on OnDeviceDownloadCancelledException {
      // 取消 → paused（.part 保留，下次 ensureModel 自动续传）
      final downloaded = await _fileSize(await _partFile());
      _emit(_snap(OnDeviceModelStatus.paused, downloadedBytes: downloaded));
      throw const OnDeviceDownloadCancelledException();
    } finally {
      if (identical(_activeToken, token)) _activeToken = null;
    }
  }

  /// 单源下载（含续传合并与双校验）；成功返回最终路径，失败抛 typed error。
  Future<String> _downloadFromSource(
    String url,
    File dest,
    ModelDownloadCancelToken token,
  ) async {
    final part = await _partFile();
    var existing = await _fileSize(part);

    // .part 已下满（上次在校验/转正前被杀）→ 直接校验转正
    if (existing >= _expectedBytes) {
      if (await _hasValidMagic(part)) {
        await part.rename(dest.path);
        return dest.path;
      }
      await part.delete(); // 魔数不对 → 废件，从头来
      existing = 0;
    }

    final resuming = existing > 0;
    final tail = await _tailFile();
    final target = resuming ? tail : part;
    if (resuming && await tail.exists()) await tail.delete();

    _emit(_snap(OnDeviceModelStatus.downloading, downloadedBytes: existing));

    final status = await _http.downloadToFile(
      url,
      target.path,
      rangeHeader: resuming ? 'bytes=$existing-' : null,
      cancelToken: token,
      onProgress: (received, total) {
        _emit(
          _snap(
            OnDeviceModelStatus.downloading,
            downloadedBytes: existing + received,
          ),
        );
      },
    );

    if (token.isCancelled) throw const OnDeviceDownloadCancelledException();

    if (status == 416 && existing >= _expectedBytes) {
      // Range 越界 = 服务端认为已下完：.part 达标直接转正
      if (resuming && await tail.exists()) await tail.delete();
      if (await _hasValidMagic(part)) {
        await part.rename(dest.path);
        return dest.path;
      }
      await part.delete();
      throw const OnDeviceCorruptModelException('416 转正时魔数校验失败，已清除');
    }
    if (status >= 400 || status == 0) {
      // 错误页/空响应写进了 target 必须清掉，无论是否续传：
      // - resuming：target 是 .tail（本次响应的垃圾段），删；
      // - 全新下载：target 是 .part，且 existing==0 → 其内容完全来自
      //   本次失败响应（HTML 错误页），删除无损失；不删则下次重试把它
      //   当断点续传，Range 追加后魔数校验才失败，白浪费一轮下载。
      if (await target.exists()) await target.delete();
      throw OnDeviceDownloadException('下载失败 HTTP $status', statusCode: status);
    }

    if (resuming) {
      if (status == 206) {
        // 服务器支持续传：剩余段追加合并到 .part
        await _appendFile(tail, part);
        await tail.delete();
      } else {
        // 服务器忽略 Range 返回整包（200）：tail 即完整文件，替换 .part
        if (await part.exists()) await part.delete();
        await tail.rename(part.path);
      }
    }

    // ---- 完整性校验：字节数 + 魔数 ----
    final size = await _fileSize(part);
    if (size < _expectedBytes) {
      throw OnDeviceCorruptModelException('下载不完整 $size/$_expectedBytes');
    }
    if (!await _hasValidMagic(part)) {
      // 下到 HTML 错误页/文件头损坏：删 .part 强制干净重下（残留断点会把脏数据续进去）
      await part.delete();
      throw const OnDeviceCorruptModelException('文件头校验失败（疑似错误页或损坏），已清除');
    }

    // 原子落盘：同目录 rename 不产生半文件窗口
    await part.rename(dest.path);
    return dest.path;
  }

  /// 流式追加（不整文件载入内存）。
  Future<void> _appendFile(File src, File dest) async {
    final out = dest.openWrite(mode: FileMode.append);
    try {
      await out.addStream(src.openRead());
    } finally {
      await out.close();
    }
  }

  /// 测试/销毁用。
  Future<void> dispose() => _controller.close();
}

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_spec.dart';
import 'package:flutter_test/flutter_test.dart';

// ==================== Fake ====================

typedef _Handler =
    Future<int> Function(
      String url,
      String savePath,
      String? rangeHeader,
      void Function(int received, int total)? onProgress,
      ModelDownloadCancelToken? cancelToken,
    );

final class _Call {
  _Call(this.url, this.rangeHeader);
  final String url;
  final String? rangeHeader;
}

/// 按 URL 排队脚本化响应的 Fake HTTP；记录每次调用（验证 Range 头/换源顺序）。
final class _FakeHttp implements ModelHttpClient {
  final _handlers = <String, Queue<_Handler>>{};
  final calls = <_Call>[];

  void on(String url, _Handler handler) {
    _handlers.putIfAbsent(url, Queue.new).add(handler);
  }

  @override
  Future<int> downloadToFile(
    String url,
    String savePath, {
    String? rangeHeader,
    void Function(int received, int total)? onProgress,
    ModelDownloadCancelToken? cancelToken,
  }) {
    calls.add(_Call(url, rangeHeader));
    final queue = _handlers[url];
    if (queue == null || queue.isEmpty) {
      throw StateError('未脚本化的下载请求：$url');
    }
    return queue.removeFirst()(
      url,
      savePath,
      rangeHeader,
      onProgress,
      cancelToken,
    );
  }
}

final class _FakeCapability implements DeviceCapabilityProbe {
  _FakeCapability({this.freeBytes, this.memoryMB});
  final int? freeBytes;
  final int? memoryMB;

  @override
  Future<int?> freeStorageBytes(String path) async => freeBytes;

  @override
  Future<int?> physicalMemoryMB() async => memoryMB;
}

// ==================== 工具 ====================

const _expected = 1024;
const _ms = OnDeviceModelSpec.modelScopeUrl;
const _hf = OnDeviceModelSpec.huggingFaceUrl;

/// 写一个 size 字节的假模型文件：头部 LITERTLM 魔数（magic=false 时为全零，
/// 模拟 HTML 错误页/损坏文件）。
Future<void> _writeModelBytes(
  String path,
  int size, {
  bool magic = true,
}) async {
  final f = File(path);
  await f.create(recursive: true);
  final raf = await f.open(mode: FileMode.write);
  try {
    if (magic) await raf.writeFrom(OnDeviceModelSpec.magicBytes);
    await raf.truncate(size); // 尾部补零到目标大小
  } finally {
    await raf.close();
  }
}

void main() {
  late Directory tmp;
  late _FakeHttp http;
  late OnDeviceModelManager manager;

  Future<String> modelPath() => manager.modelPath();
  Future<File> partFile() async => File('${await modelPath()}.part');
  Future<File> tailFile() async => File('${await modelPath()}.tail');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ondevice_test');
    http = _FakeHttp();
    manager = OnDeviceModelManager(
      http: http,
      docsDir: () async => tmp,
      deviceLocale: () => 'zh-CN', // 国内：MS 优先，GH 兜底
      operatingSystem: () => 'android',
      expectedBytes: _expected,
    );
  });

  tearDown(() async {
    await manager.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('全新下载：双校验通过后原子落盘，状态 ready', () async {
    http.on(_ms, (url, save, range, onProgress, token) async {
      expect(range, isNull, reason: '全新下载不带 Range 头');
      await _writeModelBytes(save, _expected);
      onProgress?.call(_expected, _expected);
      return 200;
    });

    final path = await manager.ensureModel();

    expect(path, endsWith('models/${OnDeviceModelSpec.fileName}'));
    expect(await File(path).length(), _expected);
    expect(
      await partFile().then((f) => f.exists()),
      isFalse,
      reason: '.part 已转正',
    );
    expect(await tailFile().then((f) => f.exists()), isFalse);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
    expect(manager.snapshot.progress, 1.0);
    expect(http.calls.map((c) => c.url), [
      _ms,
    ], reason: 'zh locale 应首选 ModelScope');
  });

  test('已就绪短路：不再发起任何下载', () async {
    await _writeModelBytes(await modelPath(), _expected);
    final path = await manager.ensureModel();
    expect(await File(path).length(), _expected);
    expect(http.calls, isEmpty);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('断点续传：.part 残留 → Range: bytes=N-，206 追加合并', () async {
    await _writeModelBytes((await partFile()).path, 600);
    http.on(_ms, (url, save, range, onProgress, token) async {
      expect(save, endsWith('.tail'), reason: '续传剩余段下到 .tail');
      await _writeModelBytes(save, _expected - 600, magic: false);
      return 206;
    });

    final path = await manager.ensureModel();

    expect(http.calls.single.rangeHeader, 'bytes=600-');
    expect(await File(path).length(), _expected);
    // 魔数在 .part 头部，合并后头部仍是 LITERTLM
    final head = await File(path).openRead(0, 8).expand((c) => c).toList();
    expect(head, OnDeviceModelSpec.magicBytes);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('服务器忽略 Range 回 200：.tail 即整包，替换 .part', () async {
    await _writeModelBytes((await partFile()).path, 600);
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected); // 整包
      return 200;
    });

    final path = await manager.ensureModel();

    expect(http.calls.single.rangeHeader, 'bytes=600-');
    expect(await File(path).length(), _expected);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('魔数校验拒绝 HTML 错误页：清除废件并自动换源', () async {
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected, magic: false); // 全零=脏文件
      return 200;
    });
    http.on(_hf, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected);
      return 200;
    });

    final path = await manager.ensureModel();

    expect(http.calls.map((c) => c.url), [_ms, _hf]);
    // 脏 .part 已删，第二源从头下（不带 Range）
    expect(http.calls[1].rangeHeader, isNull);
    expect(await File(path).length(), _expected);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('一源 HTTP 500 → 自动换源成功', () async {
    http.on(_ms, (url, save, range, onProgress, token) async => 500);
    http.on(_hf, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected);
      return 200;
    });

    await manager.ensureModel();

    expect(http.calls.map((c) => c.url), [_ms, _hf]);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('双源皆败 → error 态，抛最后一个下载错误', () async {
    http.on(_ms, (url, save, range, onProgress, token) async => 500);
    http.on(_hf, (url, save, range, onProgress, token) async => 403);

    await expectLater(
      manager.ensureModel(),
      throwsA(
        isA<OnDeviceDownloadException>().having(
          (e) => e.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
    expect(manager.snapshot.status, OnDeviceModelStatus.error);
    expect(manager.snapshot.error, isA<OnDeviceDownloadException>());
  });

  test('源 A 中断留半成品 → 源 B 从断点续传完成', () async {
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, 500); // 只下到 500 就“完成”（截断）
      return 200;
    });
    http.on(_hf, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected - 500, magic: false);
      return 206;
    });

    final path = await manager.ensureModel();

    expect(http.calls[1].rangeHeader, 'bytes=500-', reason: '半成品断点跨源保留');
    expect(await File(path).length(), _expected);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('取消 → paused 态，.part 保留，再次 ensureModel 断点续传', () async {
    final started = Completer<void>();
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, 600);
      onProgress?.call(600, _expected - 600);
      started.complete();
      final cancelled = Completer<void>();
      token?.addListener(cancelled.complete);
      await cancelled.future;
      throw const OnDeviceDownloadCancelledException();
    });

    final future = manager.ensureModel();
    await started.future;
    manager.cancel();

    await expectLater(
      future,
      throwsA(isA<OnDeviceDownloadCancelledException>()),
    );
    expect(manager.snapshot.status, OnDeviceModelStatus.paused);
    expect(manager.snapshot.downloadedBytes, 600);
    expect(
      await partFile().then((f) => f.length()),
      600,
      reason: '.part 保留供续传',
    );

    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected - 600, magic: false);
      return 206;
    });
    final states = <OnDeviceModelSnapshot>[];
    final sub = manager.snapshots.listen(states.add);
    final path = await manager.ensureModel();
    await Future<void>.delayed(Duration.zero); // 等 broadcast 事件投递
    await sub.cancel();

    expect(http.calls[1].rangeHeader, 'bytes=600-');
    final resumed = states.where(
      (s) => s.status == OnDeviceModelStatus.downloading,
    );
    expect(resumed.first.downloadedBytes, 600, reason: '续传进度从断点 N 起算，不得从 0 重爬');
    expect(await File(path).length(), _expected);
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('物理内存低于门槛 → 拦截，不发起下载', () async {
    await manager.dispose();
    manager = OnDeviceModelManager(
      http: http,
      docsDir: () async => tmp,
      deviceLocale: () => 'zh-CN',
      operatingSystem: () => 'android',
      expectedBytes: _expected,
      capability: _FakeCapability(memoryMB: 1024),
    );

    await expectLater(
      manager.ensureModel(),
      throwsA(isA<OnDeviceInsufficientMemoryException>()),
    );
    expect(http.calls, isEmpty);
    expect(manager.snapshot.status, OnDeviceModelStatus.error);
  });

  test('可用存储不足 → 拦截，不发起下载', () async {
    await manager.dispose();
    manager = OnDeviceModelManager(
      http: http,
      docsDir: () async => tmp,
      deviceLocale: () => 'zh-CN',
      operatingSystem: () => 'android',
      expectedBytes: _expected,
      capability: _FakeCapability(freeBytes: 10),
    );

    await expectLater(
      manager.ensureModel(),
      throwsA(isA<OnDeviceInsufficientStorageException>()),
    );
    expect(http.calls, isEmpty);
    expect(manager.snapshot.status, OnDeviceModelStatus.error);
  });

  test('能力探测返回 null（未知）→ 放行', () async {
    await manager.dispose();
    manager = OnDeviceModelManager(
      http: http,
      docsDir: () async => tmp,
      deviceLocale: () => 'zh-CN',
      operatingSystem: () => 'android',
      expectedBytes: _expected,
      capability: _FakeCapability(), // 全 null
    );
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected);
      return 200;
    });

    await manager.ensureModel();
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('refresh：磁盘有 .part 残留呈 paused，无残留呈 notDownloaded', () async {
    await manager.refresh();
    expect(manager.snapshot.status, OnDeviceModelStatus.notDownloaded);

    await _writeModelBytes((await partFile()).path, 300);
    await manager.refresh();
    expect(manager.snapshot.status, OnDeviceModelStatus.paused);
    expect(manager.snapshot.downloadedBytes, 300);

    await _writeModelBytes(await modelPath(), _expected);
    await manager.refresh();
    expect(manager.snapshot.status, OnDeviceModelStatus.ready);
  });

  test('delete：清除模型与临时文件，回到 notDownloaded', () async {
    await _writeModelBytes(await modelPath(), _expected);
    await _writeModelBytes((await partFile()).path, 300);

    await manager.delete();

    expect(await File(await modelPath()).exists(), isFalse);
    expect(await partFile().then((f) => f.exists()), isFalse);
    expect(manager.snapshot.status, OnDeviceModelStatus.notDownloaded);
  });

  test('下载进度经状态流播报（字节/百分比）', () async {
    http.on(_ms, (url, save, range, onProgress, token) async {
      await _writeModelBytes(save, _expected);
      onProgress?.call(256, _expected);
      onProgress?.call(_expected, _expected);
      return 200;
    });

    final states = <OnDeviceModelSnapshot>[];
    final sub = manager.snapshots.listen(states.add);
    await manager.ensureModel();
    await Future<void>.delayed(Duration.zero); // 等 broadcast 事件投递
    await sub.cancel();

    final downloading = states.where(
      (s) => s.status == OnDeviceModelStatus.downloading,
    );
    expect(downloading, isNotEmpty);
    expect(downloading.last.progress, 1.0);
    expect(states.last.status, OnDeviceModelStatus.ready);
  });

  test('Dio 取消下载保留半成品，续传带 Range: bytes=N-（deleteOnError 回归）', () async {
    // 真实 Dio + 本地 HTTP 服务，钉住「取消时 dio 不得删 .part」这条契约：
    // dio 默认 deleteOnError:true 会在取消时物理删除半成品，导致 Resume 从 0% 重下。
    const total = 4096;
    const chunk = 512;
    final body = Uint8List(total)
      ..setRange(
        0,
        OnDeviceModelSpec.magicBytes.length,
        OnDeviceModelSpec.magicBytes,
      );
    final seenRanges = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      try {
        final range = request.headers.value('range');
        seenRanges.add(range);
        final match = range == null
            ? null
            : RegExp(r'bytes=(\d+)-').firstMatch(range);
        final start = match == null ? 0 : int.parse(match.group(1)!);
        request.response.statusCode = start > 0 ? 206 : 200;
        if (start > 0) {
          request.response.headers.set(
            'content-range',
            'bytes $start-${total - 1}/$total',
          );
        }
        // 分块慢发给取消留出窗口；bufferOutput=false 才会真正逐块下发
        //（默认缓冲会把 4KB 整包一次性塞给客户端，取消永远落在下完之后）
        request.response.bufferOutput = false;
        request.response.contentLength = total - start;
        for (var i = start; i < total; i += chunk) {
          final end = i + chunk > total ? total : i + chunk;
          request.response.add(body.sublist(i, end));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await request.response.close();
      } on Object {
        // 客户端取消后写半关断的连接会抛 broken pipe，忽略
      }
    });
    final url = 'http://127.0.0.1:${server.port}/model.litertlm';
    final client = DioModelHttpClient();

    // 首下：收到首批字节即取消（模拟设置页 Cancel）
    final token = ModelDownloadCancelToken();
    final partPath = '${tmp.path}/dio_cancel.part';
    await expectLater(
      client.downloadToFile(
        url,
        partPath,
        cancelToken: token,
        onProgress: (received, totalBytes) {
          if (received > 0 && !token.isCancelled) token.cancel();
        },
      ),
      throwsA(isA<OnDeviceDownloadCancelledException>()),
    );

    // dio 的 deleteOnError 删除是异步的（取消后 await 订阅取消 + 关文件
    // 才删），立刻检查会漏抓回归——轮询一个删除窗口确认文件始终存活。
    var kept = 0;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!await File(partPath).exists()) break;
      kept = await File(partPath).length();
    }
    expect(
      await File(partPath).exists(),
      isTrue,
      reason: '取消后 .part 不得被删除（deleteOnError 回归）',
    );
    expect(kept, greaterThan(0), reason: '取消后已下字节必须保留供续传');
    expect(kept, lessThan(total), reason: '取消发生在下完之前');
    expect(seenRanges.single, isNull, reason: '首下不带 Range 头');

    // 续传：剩余段带 Range: bytes=N-，服务器回 206
    final tailPath = '$partPath.tail';
    final status = await client.downloadToFile(
      url,
      tailPath,
      rangeHeader: 'bytes=$kept-',
    );
    expect(status, 206);
    expect(seenRanges.last, 'bytes=$kept-');
    expect(await File(tailPath).length(), total - kept);
  });
  group('错误页污染清理（HTTP >=400 必删 target）', () {
    test('全新下载 404：垃圾错误页写入 .part → 必须清除（不留下次续传污染源）', () async {
      // 双源都 404 且把 HTML 错误页写进 savePath（dio validateStatus 全放行
      // 的真实行为）。
      for (final url in [_ms, _hf]) {
        http.on(url, (u, save, range, onProgress, token) async {
          expect(range, isNull, reason: '全新下载不带 Range 头');
          await File(save).writeAsString('<html>404 not found</html>');
          return 404;
        });
      }

      await expectLater(
        manager.ensureModel(),
        throwsA(isA<OnDeviceDownloadException>()),
      );

      // 修复前：垃圾 HTML 残留 .part，下次重试被当断点续传污染源。
      expect(await (await partFile()).exists(), isFalse);
      expect(manager.snapshot.status, OnDeviceModelStatus.error);
    });

    test('续传下载 404：垃圾写入 .tail 被删；已有断点 .part 原样保留', () async {
      // 预置断点：.part 已有 512 字节（含魔数头部）。
      await (await partFile()).create(recursive: true);
      await _writeModelBytes((await partFile()).path, 512);
      for (final url in [_ms, _hf]) {
        http.on(url, (u, save, range, onProgress, token) async {
          expect(range, 'bytes=512-', reason: '续传带 Range 头');
          await File(save).writeAsString('<html>404 not found</html>');
          return 404;
        });
      }

      await expectLater(
        manager.ensureModel(),
        throwsA(isA<OnDeviceDownloadException>()),
      );

      expect(await (await tailFile()).exists(), isFalse, reason: '.tail 垃圾段已清');
      final part = await partFile();
      expect(await part.exists(), isTrue, reason: '已有断点不删');
      expect(await part.length(), 512);
    });
  });

  group('error 快照保留断点进度', () {
    test('下载失败且 .part 已存 N 字节 → error 快照 downloadedBytes == N', () async {
      const preset = 300;
      await (await partFile()).create(recursive: true);
      await _writeModelBytes((await partFile()).path, preset);
      for (final url in [_ms, _hf]) {
        http.on(url, (u, save, range, onProgress, token) async {
          throw const OnDeviceDownloadException('网络中断', statusCode: 0);
        });
      }

      await expectLater(
        manager.ensureModel(),
        throwsA(isA<OnDeviceDownloadException>()),
      );

      final snapshot = manager.snapshot;
      expect(snapshot.status, OnDeviceModelStatus.error);
      expect(snapshot.downloadedBytes, preset);
      expect(snapshot.totalBytes, _expected);
      expect(snapshot.progress, closeTo(preset / _expected, 0.001));
    });
  });
}

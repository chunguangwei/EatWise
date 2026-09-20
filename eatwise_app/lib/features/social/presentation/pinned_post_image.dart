import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 帖图字节加载器（URL → 字节；失败返回 null 由 UI 走占位图）。
typedef PostImageFetcher = Future<Uint8List?> Function(String url);

/// 带内存缓存的帖图加载器：feed 滚动重建不重复拉网络；缓存满按
/// FIFO 逐出（帖图为缩略卡尺寸，64 张 ≈ 几 MB，够一屏 + 预取窗口）。
final class PinnedPostImageLoader {
  PinnedPostImageLoader(this._fetch);

  final PostImageFetcher _fetch;
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static const int _maxEntries = 64;

  Future<Uint8List?> load(String url) async {
    final hit = _cache[url];
    if (hit != null) return hit;
    final bytes = await _fetch(url);
    if (bytes != null && bytes.isNotEmpty) {
      if (_cache.length >= _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[url] = bytes;
    }
    return bytes;
  }
}

/// 帖图加载器（走 [apiDioProvider]：自带自签名证书锁定 / 401 续期 /
/// 错误映射；`Image.network` 的裸 HttpClient 不挂 cert pinning，
/// 生产 https://wcg.polin.tech 握手必失败 → 断图，故 feed 图一律
/// 经此拉字节后 [Image.memory] 渲染）。
final Provider<PinnedPostImageLoader> pinnedPostImageLoaderProvider =
    Provider<PinnedPostImageLoader>((ref) {
      final dio = ref.watch(apiDioProvider);
      return PinnedPostImageLoader((url) async {
        try {
          final response = await dio.get<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes),
          );
          final data = response.data;
          return data == null ? null : Uint8List.fromList(data);
        } on Object {
          return null; // 任意失败（404/断网/TLS）→ UI 占位图（§3.2.4）。
        }
      });
    });

/// 社区帖配图：经 pinning dio 拉字节渲染；加载中留空、失败断图占位
/// （与旧 `Image.network` 的 loadingBuilder/errorBuilder 语义一致）。
class PinnedPostImage extends ConsumerStatefulWidget {
  const PinnedPostImage({
    required this.url,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String url;
  final BoxFit fit;

  @override
  ConsumerState<PinnedPostImage> createState() => _PinnedPostImageState();
}

class _PinnedPostImageState extends ConsumerState<PinnedPostImage> {
  Future<Uint8List?>? _future;
  String? _futureUrl;

  void _ensureLoading() {
    if (_futureUrl == widget.url && _future != null) return;
    _futureUrl = widget.url;
    _future = ref.read(pinnedPostImageLoaderProvider).load(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoading();
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          final colors = Theme.of(context).extension<AppColors>()!;
          return ColoredBox(
            color: colors.bgPrimary,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: colors.textSecondary,
                size: 48,
              ),
            ),
          );
        }
        return Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
      },
    );
  }
}

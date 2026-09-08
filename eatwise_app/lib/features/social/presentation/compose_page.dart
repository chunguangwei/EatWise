import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 打卡配图选择（复用 M3 拍照/相册抽象，便于测试注入 fake）。
final composePhotoPickerProvider = Provider<PhotoPickerGateway>((ref) {
  return ImagePickerPhotoGateway();
});

/// 打卡发布页（M5：文字 ≤500 字计数 + 配图 + streak 徽章 + 乐观发布）。
///
/// 配图链路：选图即上传（POST /uploads，U1）→ 拿到 `/v1/uploads/<id>` →
/// 发布时作为 imageUrls 上行。上传中禁用发布（避免发出无图帖），失败提供
/// 就地重试；预览上传前用本地字节、成功后切网络图。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  static const int maxChars = 500;

  final TextEditingController _controller = TextEditingController();
  Uint8List? _photo;
  String? _photoUrl;
  bool _uploading = false;

  /// 上传失败文案（服务端本地化 message 优先，网络类失败用本地兜底文案）。
  String? _uploadError;

  /// 上传代际：移除/换图后丢弃在途回调，避免旧图 URL 覆盖新图。
  int _uploadSeq = 0;

  bool get _photoReady => _photo == null || _photoUrl != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final bytes = await ref
          .read(composePhotoPickerProvider)
          .pick(PhotoSource.gallery);
      if (bytes == null || !mounted) return;
      setState(() {
        _photo = bytes;
        _photoUrl = null;
      });
      await _uploadPhoto(bytes);
    } on PhotoPermissionDeniedException {
      // 权限拒绝不阻断文字发布（§4.3 降级）。
    }
  }

  /// 上传图片（U1）。失败只影响配图，不阻断文字发布路径。
  Future<void> _uploadPhoto(Uint8List bytes) async {
    final seq = ++_uploadSeq;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final uploaded = await ref.read(uploadApiProvider).uploadImage(bytes);
      if (!mounted || seq != _uploadSeq) return;
      setState(() {
        _photoUrl = uploaded.url;
        _uploading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _uploadSeq) return;
      // 业务错误（超限/非法类型）直接上屏服务端双语 message（D-15）。
      setState(() {
        _uploading = false;
        _uploadError = e.message;
      });
    }
  }

  Future<void> _publish() async {
    final t = Translations.of(context);
    final text = _controller.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (text.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(t.social.compose.emptyText)),
      );
      return;
    }
    if (_uploading || !_photoReady) {
      // 配图未就绪：不发无图帖，也不让用户以为发成功了。
      messenger.showSnackBar(
        SnackBar(content: Text(t.social.compose.photoUploading)),
      );
      return;
    }
    setState(() => _submitting = true);
    final streakDays = ref.read(streakControllerProvider).currentStreak;
    final result = await ref
        .read(feedControllerProvider.notifier)
        .publish(
          text: text,
          imageUrls: _photoUrl == null
              ? const <String>[]
              : <String>[_photoUrl!],
          streakDays: streakDays > 0 ? streakDays : null,
        );
    if (!mounted) return;
    switch (result) {
      case PublishOk():
        context.pop();
      case PublishRejected(:final message):
        // 先审后发拒绝：服务端双语提示直接上屏（D-17）。
        messenger.showSnackBar(SnackBar(content: Text(message)));
        setState(() => _submitting = false);
      case PublishFailed():
        messenger.showSnackBar(
          SnackBar(content: Text(t.social.compose.publishFailed)),
        );
        setState(() => _submitting = false);
    }
  }

  bool _submitting = false;

  /// 配图区：本地预览（上传前）→ 网络图（上传后）+ 上传态/失败重试。
  Widget _buildPhotoSection(Translations t) {
    final photo = _photo;
    if (photo == null) {
      return OutlinedButton.icon(
        onPressed: _pickPhoto,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(t.social.compose.addPhoto),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.s12),
        ),
      );
    }

    final url = _photoUrl;
    // 服务端回的是相对路径（契约自带 /v1 前缀），渲染前补 origin。
    final absoluteUrl = url == null
        ? null
        : ref.read(apiConfigProvider).resolveUrl(url);
    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // 上传成功前用本地字节（选图即刻可见），之后走网络图。
              child: absoluteUrl == null
                  ? Image.memory(
                      photo,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      absoluteUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // 网络图首帧前继续显示本地图，避免闪烁。
                      loadingBuilder: (context, child, progress) =>
                          Image.memory(
                            photo,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                      errorBuilder: (context, error, stackTrace) =>
                          Image.memory(
                            photo,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                    ),
            ),
            if (_uploading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Semantics(
                      label: t.social.compose.photoUploading,
                      child: const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: AppSpacing.s1,
              right: AppSpacing.s1,
              child: IconButton.filled(
                icon: const Icon(Icons.close),
                tooltip: t.social.compose.removePhoto,
                onPressed: () => setState(() {
                  // 递增代际作废在途上传，已上传的图不回收（帖子里可复用）。
                  _uploadSeq++;
                  _photo = null;
                  _photoUrl = null;
                  _uploading = false;
                  _uploadError = null;
                }),
              ),
            ),
          ],
        ),
        if (_uploadError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _uploadError ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _uploadPhoto(photo),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t.social.compose.retryUpload),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final streak = ref.watch(streakControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.social.compose.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            // streak 徽章（D-12：打卡带连续天数；0 不显示数字徽章，改引导文案 4.2）。
            Container(
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: colors.brandAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.local_fire_department, color: colors.brandAccent),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      streak.currentStreak > 0
                          ? t.social.compose.streakBadge(
                              days: streak.currentStreak,
                            )
                          : t.social.compose.noStreak,
                      style: textStyles.textSm,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            // 文字输入（≤500 字计数，契约 §3.9 C1）。
            TextField(
              controller: _controller,
              maxLines: 6,
              maxLength: maxChars,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => Text(
                    t.social.compose.charCount(n: currentLength),
                    style: textStyles.textXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t.social.compose.hint,
                filled: true,
                fillColor: colors.bgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 配图：选图即上传，上传中禁用发布。
            _buildPhotoSection(t),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: _submitting || _uploading ? null : _publish,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                t.social.compose.publish,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

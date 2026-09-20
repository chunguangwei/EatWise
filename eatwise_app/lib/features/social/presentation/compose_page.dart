import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/application/post_polish_providers.dart';
import 'package:eatwise/features/social/application/post_polish_service.dart';
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
/// 发布时作为 imageUrls 上行。上传中禁用发布（避免发出缺图帖），失败提供
/// 就地重试，且发布时可选「不带图发布」（失败不阻断文字发布）；预览恒用
/// 本地字节。AI 润色（端侧视觉模型，结合配图）回填输入框，可一键撤销。
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

  /// AI 润色在途标志 + 当前阶段（null = 不在润色）。
  bool _polishing = false;
  PostPolishPhase? _polishPhase;

  /// 润色前原文（撤销用；一次撤销后清空，再润色重新快照）。
  String? _prePolishText;

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

  /// AI 润色：端侧视觉模型结合原文 + 配图生成润色文案，成功回填输入框
  /// （原文快照供撤销）；失败 snackbar 提示，不阻断发布。
  Future<void> _polish() async {
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(postPolishServiceProvider);
    final text = _controller.text.trim();
    if (service == null || _polishing || text.isEmpty) return;
    setState(() {
      _polishing = true;
      _polishPhase = null;
    });
    service.onPhaseChanged = (phase) {
      if (mounted) setState(() => _polishPhase = phase);
    };
    PostPolishResult result;
    try {
      result = await service.polish(text, imageBytes: _photo);
    } finally {
      service.onPhaseChanged = null;
    }
    if (!mounted) return;
    switch (result) {
      case PostPolishOk(:final text):
        setState(() {
          _prePolishText = _controller.text;
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          _polishing = false;
          _polishPhase = null;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.social.compose.polishDone),
            action: SnackBarAction(
              label: t.social.compose.polishUndo,
              onPressed: _undoPolish,
            ),
          ),
        );
      case PostPolishUnavailable():
        setState(() {
          _polishing = false;
          _polishPhase = null;
        });
        messenger.showSnackBar(
          SnackBar(content: Text(t.social.compose.polishFailed)),
        );
    }
  }

  /// 撤销润色：回填润色前原文（snackbar「撤销润色」入口触发）。
  void _undoPolish() {
    final original = _prePolishText;
    if (original == null) return;
    setState(() {
      _prePolishText = null;
      _controller.value = TextEditingValue(
        text: original,
        selection: TextSelection.collapsed(offset: original.length),
      );
    });
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
    if (_uploading) {
      // 上传在途：等传完再发，避免发出缺图帖。
      messenger.showSnackBar(
        SnackBar(content: Text(t.social.compose.photoUploading)),
      );
      return;
    }
    if (_photo != null && _photoUrl == null) {
      // 上传失败不阻断文字发布：用户选「不带图发布」则丢弃失败配图按纯
      // 文字帖继续，取消则保留配图与就地重试入口。
      final dropPhoto = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(t.social.compose.photoUploadFailedBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t.common.action.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t.social.compose.publishWithoutPhoto),
            ),
          ],
        ),
      );
      if (dropPhoto != true || !mounted) return;
      setState(() {
        _photo = null;
        _uploadError = null;
      });
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

    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // 预览恒用本地字节：选图即刻可见，上传成功切网络图在
              // 自签证书下反而引入加载失败面（无收益）。
              child: Image.memory(
                photo,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
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
            // AI 润色（端侧视觉模型；服务为 null = 开关关/模型未就绪 →
            // 隐藏入口，发布主流程不受影响）。
            if (ref.watch(postPolishServiceProvider) != null) ...<Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _polishing || _controller.text.trim().isEmpty
                      ? null
                      : _polish,
                  icon: _polishing
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: Text(switch ((_polishing, _polishPhase)) {
                    (true, PostPolishPhase.loadingModel) =>
                      t.social.compose.polishLoadingModel,
                    (true, _) => t.social.compose.polishInferring,
                    (false, _) => t.social.compose.polish,
                  }),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s2),
            // 配图：选图即上传，上传中禁用发布；失败可重试或不带图发布。
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

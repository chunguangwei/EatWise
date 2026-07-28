import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
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

/// 打卡发布页（M5 P1：文字 ≤500 字计数 + 可选图片本地预览 +
/// 当前 streak 徽章 + 乐观发布）。
///
/// 〔假设〕MVP 图片仅本地预览，上行链路（POST /uploads/images → CDN 直传）
/// 留 TODO：选图后发布仍走纯文本，UI 明示「图片上传即将支持」。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  static const int maxChars = 500;

  final TextEditingController _controller = TextEditingController();
  Uint8List? _photo;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final t = Translations.of(context);
    try {
      final bytes = await ref
          .read(composePhotoPickerProvider)
          .pick(PhotoSource.gallery);
      if (bytes != null && mounted) {
        setState(() => _photo = bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.social.compose.photoUploadTodo)),
        );
      }
    } on PhotoPermissionDeniedException {
      // 权限拒绝不阻断文字发布（§4.3 降级）。
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
    setState(() => _submitting = true);
    final streakDays = ref.read(streakControllerProvider).currentStreak;
    final result = await ref
        .read(feedControllerProvider.notifier)
        .publish(text: text, streakDays: streakDays > 0 ? streakDays : null);
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
            // 图片：本地预览 + 移除（上传链路 TODO，见类注释）。
            if (_photo != null)
              Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _photo!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.s1,
                    right: AppSpacing.s1,
                    child: IconButton.filled(
                      icon: const Icon(Icons.close),
                      tooltip: t.social.compose.removePhoto,
                      onPressed: () => setState(() => _photo = null),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(t.social.compose.addPhoto),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
              ),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: _submitting ? null : _publish,
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

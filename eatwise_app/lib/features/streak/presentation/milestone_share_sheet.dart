import 'dart:io';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/streak/presentation/milestone_share_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

/// 分享执行通道（插件依赖收口于此接口，测试注入内存假实现，
/// 避免 share_plus / saver_gallery 在 widget 测试中
/// 抛 MissingPluginException）。
abstract interface class ShareCardActions {
  /// 系统分享 sheet（PNG 文件）。
  Future<void> shareSystem(Uint8List png, String fileName);

  /// 保存相册，返回是否成功。
  Future<bool> saveToAlbum(Uint8List png, String fileName);
}

/// 生产实现：share_plus（系统分享 sheet）+ saver_gallery（保存相册）。
final class PluginShareCardActions implements ShareCardActions {
  const PluginShareCardActions();

  @override
  Future<void> shareSystem(Uint8List png, String fileName) async {
    // share_plus 分享文件需先落临时目录。
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path, mimeType: 'image/png')]),
    );
  }

  @override
  Future<bool> saveToAlbum(Uint8List png, String fileName) async {
    final result = await SaverGallery.saveImage(
      png,
      fileName: fileName,
      skipIfExists: false,
    );
    return result.isSuccess;
  }
}

/// 里程碑分享预览底部弹页（US-5.1：徽章点按 → 图卡预览 +
/// 「保存到相册」+「系统分享」）。
///
/// 埋点（《埋点规范与事件字典》）：
/// - `share_card_expose`：弹页展示（session 内按里程碑档位去重，§4.1）；
/// - `share_click`：分享点击（channel=system/save_image，字典既有事件）；
/// - `share_card_saved`：保存相册成功。
class MilestoneShareSheet extends StatefulWidget {
  const MilestoneShareSheet({
    required this.days,
    required this.analytics,
    this.actions = const PluginShareCardActions(),
    this.date,
    super.key,
  });

  /// 里程碑档位（3/7/30；图卡大数字与埋点 milestone 属性）。
  final int days;

  /// 埋点服务（由调用方从 Provider 读出注入，便于测试替换）。
  final AnalyticsService analytics;

  /// 分享执行通道（生产默认插件实现；测试注入假实现）。
  final ShareCardActions actions;

  /// 图卡日期（yyyy-MM-dd；默认当日，测试注入固定值）。
  final String? date;

  @override
  State<MilestoneShareSheet> createState() => _MilestoneShareSheetState();
}

class _MilestoneShareSheetState extends State<MilestoneShareSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 图卡曝光（§4.1：session 内同一里程碑档位只计一次）。
    widget.analytics.trackExpose(
      'share_card_expose',
      dedupeKey: 'share_card:badge:${widget.days}',
      properties: <String, Object?>{
        'share_type': 'badge',
        'milestone': widget.days,
        'streak_days': widget.days,
      },
    );
  }

  String get _date {
    final injected = widget.date;
    if (injected != null) return injected;
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String get _fileName => 'eatwise_streak_${widget.days}d.png';

  Future<void> _saveToAlbum() async {
    final t = Translations.of(context);
    widget.analytics.track(
      'share_click',
      properties: <String, Object?>{
        'share_type': 'badge',
        'channel': 'save_image',
        'milestone': widget.days,
      },
    );
    setState(() => _busy = true);
    try {
      final png = await captureShareCardPng(_boundaryKey);
      final ok = await widget.actions.saveToAlbum(png, _fileName);
      if (!mounted) return;
      if (ok) {
        widget.analytics.track(
          'share_card_saved',
          properties: <String, Object?>{
            'share_type': 'badge',
            'milestone': widget.days,
          },
        );
        _toast(t.streak.milestone.shareCard.saveSuccess);
      } else {
        _toast(t.streak.milestone.shareCard.saveFailed);
      }
    } on Object {
      if (mounted) _toast(t.streak.milestone.shareCard.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareSystem() async {
    final t = Translations.of(context);
    widget.analytics.track(
      'share_click',
      properties: <String, Object?>{
        'share_type': 'badge',
        'channel': 'system',
        'milestone': widget.days,
      },
    );
    setState(() => _busy = true);
    try {
      final png = await captureShareCardPng(_boundaryKey);
      await widget.actions.shareSystem(png, _fileName);
    } on Object {
      if (mounted) _toast(t.streak.milestone.shareCard.shareFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    // 图卡中英双语：无论当前语种，物料均为主中文 + 副英文（出海分享物料）。
    final zh = AppLocale.zhCn.buildSync();
    final en = AppLocale.en.buildSync();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          0,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              t.streak.milestone.shareCard.sheetTitle,
              style: textStyles.textLg.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s3),
            // 图卡预览：1080×1350 固定设计稿经 FittedBox 等比缩放；
            // RepaintBoundary 供导出（导出尺寸与设计稿一致，与预览缩放无关）。
            Flexible(
              child: ClipRRect(
                borderRadius: radii.rLg,
                child: AspectRatio(
                  aspectRatio:
                      MilestoneShareCard.designWidth /
                      MilestoneShareCard.designHeight,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: MilestoneShareCard(
                        days: widget.days,
                        date: _date,
                        primaryTitle: zh.streak.milestone.title(
                          days: '${widget.days}',
                        ),
                        secondaryTitle: en.streak.milestone.title(
                          days: '${widget.days}',
                        ),
                        daysUnit: t.streak.milestone.shareCard.daysUnit,
                        appName: t.streak.milestone.shareCard.appName,
                        tagline: t.streak.milestone.shareCard.tagline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _saveToAlbum,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.border),
                      foregroundColor: colors.textPrimary,
                      minimumSize: const Size(0, AppSpacing.s12),
                    ),
                    child: Text(t.streak.milestone.shareCard.saveToAlbum),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _shareSystem,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                      minimumSize: const Size(0, AppSpacing.s12),
                    ),
                    child: Text(
                      t.streak.milestone.shareCard.shareSystem,
                      style: textStyles.textBase.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 徽章点按入口：底部弹出分享预览页（US-5.1）。
Future<void> showMilestoneShareSheet(
  BuildContext context, {
  required int days,
  required AnalyticsService analytics,
  ShareCardActions? actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => MilestoneShareSheet(
      days: days,
      analytics: analytics,
      actions: actions ?? const PluginShareCardActions(),
    ),
  );
}

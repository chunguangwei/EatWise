import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:flutter/material.dart';

/// 自定义进食窗口编辑器（进食窗口自选：ModalBottomSheet）。
///
/// 时长 chips（10h/8h/6h）+ [showTimePicker] 选开始时间 + 实时预览
/// 「进食 HH:mm–HH:mm · 禁食 X 小时」+「重置为推荐窗口」（D-03 默认窗口
/// 起点预填）。确认弹出 [FastingWindowDraft]，取消/下滑关闭弹出 null；
/// 生效时序（首启立即 / T12 次日）由调用方按既有启动/换方案路径处理。
class WindowEditorSheet extends StatefulWidget {
  const WindowEditorSheet({
    super.key,
    required this.initialEatingHours,
    required this.initialStartMinutes,
  });

  /// 弹出编辑器；确认返回草稿，关闭返回 null。
  static Future<FastingWindowDraft?> show(
    BuildContext context, {
    required int initialEatingHours,
    required int initialStartMinutes,
  }) {
    return showModalBottomSheet<FastingWindowDraft>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => WindowEditorSheet(
        initialEatingHours: initialEatingHours,
        initialStartMinutes: initialStartMinutes,
      ),
    );
  }

  /// 初始进食时长（小时，取当前方案的窗口时长）。
  final int initialEatingHours;

  /// 初始进食窗口开始（本地墙钟分钟数）。
  final int initialStartMinutes;

  /// 可选时长（由松到紧，与设计顺序一致）。
  static const List<int> _hourChoices = <int>[10, 8, 6];

  @override
  State<WindowEditorSheet> createState() => _WindowEditorSheetState();
}

class _WindowEditorSheetState extends State<WindowEditorSheet> {
  late int _eatingHours =
      WindowEditorSheet._hourChoices.contains(widget.initialEatingHours)
      ? widget.initialEatingHours
      : 8;
  late int _startMinutes = widget.initialStartMinutes.clamp(0, 24 * 60 - 1);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final draft = buildWindow(
      eatingHours: _eatingHours,
      startMinutes: _startMinutes,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s4,
          AppSpacing.s4,
          AppSpacing.s4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.fasting.window.title,
              style: textStyles.textLg.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              t.fasting.window.duration,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s2),
            Wrap(
              spacing: AppSpacing.s2,
              children: <Widget>[
                for (final hours in WindowEditorSheet._hourChoices)
                  FilterChip(
                    key: ValueKey<String>('fasting.windowEditor.hours.$hours'),
                    label: Text(t.fasting.window.hoursOption(hours: hours)),
                    selected: hours == _eatingHours,
                    onSelected: (_) => setState(() => _eatingHours = hours),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            InkWell(
              key: const ValueKey<String>('fasting.windowEditor.start'),
              onTap: _pickStartTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        t.fasting.window.start,
                        style: textStyles.textBase.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      formatClock(_startMinutes),
                      style: textStyles.textBase.copyWith(
                        color: colors.brandPrimary,
                      ),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.fasting.window.preview(
                window: formatWindow(draft.startMinutes, draft.endMinutes),
                hours: draft.fastingHours,
              ),
              key: const ValueKey<String>('fasting.windowEditor.preview'),
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('fasting.windowEditor.reset'),
                onPressed: () => setState(
                  () => _startMinutes = recommendedStartMinutes(_eatingHours),
                ),
                child: Text(t.fasting.window.resetRecommended),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            FilledButton(
              key: const ValueKey<String>('fasting.windowEditor.confirm'),
              onPressed: () => Navigator.of(context).pop(draft),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(t.fasting.window.confirm, style: textStyles.textBase),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _startMinutes ~/ 60,
        minute: _startMinutes % 60,
      ),
    );
    if (picked == null) return;
    setState(() => _startMinutes = picked.hour * 60 + picked.minute);
  }
}

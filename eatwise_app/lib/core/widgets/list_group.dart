import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 分组列表族（2026-09-30 UI 换代共享组件，华为「我的 / 我的数据」页语言）：
/// 灰底分组标题 + 纯白圆角卡 + 线性图标行 + 缩进发丝线 + 右侧值 + chevron。
///
/// 取代此前设置页各自手写的 `_SettingsTile`/分隔线拼装：行高、图标徽标尺寸、
/// 发丝线缩进、chevron 样式全部收敛到本文件，页面只描述「有哪些行」。

/// 分组标题（卡外灰色小标题，如「数据」「其他」）。
class ListSectionHeader extends StatelessWidget {
  const ListSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s1,
        AppSpacing.s4,
        AppSpacing.s1,
        AppSpacing.s2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 纯白圆角分组卡：自动在相邻行之间插入缩进发丝线。
///
/// 发丝线缩进量与行内图标槽宽度对齐（图标 + 间距），华为列表的整洁感
/// 主要来自这条「不顶头」的分隔线——全宽分隔线会把列表切得很碎。
class ListGroupCard extends StatelessWidget {
  const ListGroupCard({
    super.key,
    required this.children,
    this.dividerIndent = 52,
  });

  final List<Widget> children;

  /// 发丝线左缩进（默认 52 = 图标徽标 36 + 间距 12 + 卡内边距余量）。
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                color: colors.divider,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 列表行：线性图标 + 标题（+ 副标题）+ 右侧值/自定义尾部 + chevron。
///
/// 中英文适配：标题与右侧值共享一行宽度，标题 [Flexible] 可收缩、
/// 右侧值 [Flexible] 且 ellipsis——英文标题（如 "Notification settings"）
/// 与长数值同时出现时不会互相挤爆；副标题独占一行不参与竞争。
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.enabled = true,
  });

  /// 线性图标（null 则不占图标槽，行文本左对齐到卡内边距）。
  final IconData? icon;

  /// 图标色（null 走次要色——华为「我的数据」页统一中性灰线性图标）。
  final Color? iconColor;

  final String title;
  final String? subtitle;

  /// 右侧值文本（如「2,788 步」）。
  final String? value;

  /// 自定义尾部（Switch 等；与 [value] 互斥，优先生效）。
  final Widget? trailing;

  final VoidCallback? onTap;

  /// 是否显示右箭头（有 [trailing] 时通常关闭）。
  final bool showChevron;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final disabled = !enabled;
    final titleColor = disabled ? colors.textSecondary : colors.textPrimary;

    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 22, color: iconColor ?? colors.textSecondary),
              const SizedBox(width: AppSpacing.s3),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: textStyles.textBase.copyWith(color: titleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            if (trailing != null)
              trailing!
            else if (value != null)
              Flexible(
                child: Text(
                  value!,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (showChevron && trailing == null) ...<Widget>[
              const SizedBox(width: AppSpacing.s1),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.textSecondary.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

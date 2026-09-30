import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 指标卡（2026-09-29 UI 重构共享组件，华为运动健康看板语言）：
/// 圆形浅色图标徽标 + 小标签 + textDisplay 大数字与单位 + 可选迷你进度条/
/// 说明行。2 列网格场景由父级布局决定（本组件占满给定宽度）。
///
/// 纯展示：所有数值由调用方传入；文案走 i18n（调用方给字符串，不在组件
/// 内硬编码）。
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.unit,
    this.progress,
    this.caption,
    this.onTap,
    this.iconWidget,
  });

  /// 图标（Material Icon；[iconWidget] 优先）。
  final IconData icon;

  /// 图标与进度条强调色（Token 取值，如 ringStand/ringExercise/chartPurple）。
  final Color iconColor;

  /// 小标签（次要色，如「今日热量」）。
  final String label;

  /// 大数字文本（textDisplay；如「1,610」）。
  final String value;

  /// 单位（textSm 次要色，紧随大数字；如「千卡」）。
  final String? unit;

  /// 0..1 迷你进度条（null 不渲染）。
  final double? progress;

  /// 底部说明行（textXs 次要色；如「目标 2,000 千卡」）。
  final String? caption;

  final VoidCallback? onTap;

  /// 自定义徽标（emoji/图形等；优先于 [icon]）。
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Material(
      color: colors.bgSecondary,
      borderRadius: radii.rLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: radii.rLg,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: radii.rLg,
            boxShadow: shadows.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: iconWidget ?? Icon(icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      label,
                      style: textStyles.textSm.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: textStyles.textDisplay.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                  if (unit != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.s1),
                    Text(
                      unit!,
                      style: textStyles.textSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s3),
                ClipRRect(
                  borderRadius: radii.rFull,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: colors.textSecondary.withValues(
                      alpha: 0.15,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                ),
              ],
              if (caption != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  caption!,
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
      ),
    );
  }
}

/// 图表卡（2026-09-30 UI 换代共享组件，华为「心脏健康/睡眠/血氧」卡语言）：
/// 标题 + 大数字值行 + 迷你图表区 + 可选底部说明/动作行。
///
/// 与 [MetricCard] 的分工：MetricCard 表达「单值 + 目标进度」，
/// ChartCard 表达「单值 + 形状趋势」。图表本体由调用方传入（[chart]），
/// 本组件只负责卡片骨架与排版，不感知图表类型。
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.value,
    this.valuePrefix,
    this.unit,
    this.chart,
    this.caption,
    this.onTap,
    this.accentColor,
  });

  /// 卡标题（主色，如「心脏健康」）。
  final String title;

  /// 大数字（textDisplay；如「88」）。
  final String value;

  /// 大数字前的小标签（次要色，如「心率」——华为卡内「心率 88 次/分钟」形态）。
  final String? valuePrefix;

  /// 单位（次要色，紧随大数字）。
  final String? unit;

  /// 迷你图表（`MiniSparkline`/`MiniBars`/`MiniSegmentBar` 等；null 不占位）。
  final Widget? chart;

  /// 底部说明行（次要色小字，如「日均静息心率比上月高↑」）。
  final String? caption;

  final VoidCallback? onTap;

  /// 强调色（保留给调用方统一卡内配色；当前仅用于语义，不改骨架）。
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Material(
      color: colors.bgSecondary,
      borderRadius: radii.rLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: radii.rLg,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: radii.rLg,
            boxShadow: shadows.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: textStyles.textBase.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s2),
              // 值行整体 FittedBox 缩放：中英文单位长度差异大
              //（「次/分钟」vs "bpm"、「小时」vs "hours"），窄屏 2 列网格下
              // 必须允许整体缩放而不是让单位换行。
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (valuePrefix != null) ...<Widget>[
                      Text(
                        valuePrefix!,
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s1),
                    ],
                    Text(
                      value,
                      style: textStyles.textDisplay.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (unit != null) ...<Widget>[
                      const SizedBox(width: AppSpacing.s1),
                      Text(
                        unit!,
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (chart != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s3),
                chart!,
              ],
              if (caption != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  caption!,
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
      ),
    );
  }
}

/// 区块头（2026-09-29 UI 重构共享组件）：标题 + 可选尾部动作（如「查看详情」）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;

  /// 尾部动作（通常为 TextButton/小字链接）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: textStyles.textXl.copyWith(color: colors.textPrimary),
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

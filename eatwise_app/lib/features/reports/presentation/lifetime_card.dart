import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 断食累计成果卡（2026-09-30 新增）。
///
/// 补齐「长期数据」的总量视角：趋势图回答「最近怎么样」，本卡回答
/// 「一共坚持了多少」。此前二者皆无——用户断食几个月，除了连胜天数
/// 看不到任何累计成果，长期坚持缺少正反馈。
///
/// 口径说明（与 `computeFastingLifetime` 一致）：
/// - 累计时长/最长单次/达标平均时长**只算真实断食**，补签日不计；
/// - 达标天数与历史达标率**包含补签**（补签卡本就是达标凭证）。
class FastingLifetimeCard extends ConsumerWidget {
  const FastingLifetimeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final copy = t.reports.lifetime;
    final stats = ref.watch(fastingLifetimeProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.title,
            style: textStyles.textLg.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s3),
          if (!stats.hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
              child: Text(
                copy.empty,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            )
          else ...<Widget>[
            // 2×2 统计格。窄屏 + 大字体下长值（如「1,234」小时）易截断，
            // 每格数值走 FittedBox 缩放，与成长轨迹四格同口径。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _Stat(
                    label: copy.totalHours,
                    value: stats.totalHours.toStringAsFixed(0),
                    unit: copy.totalHoursUnit,
                    color: colors.ringExercise,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: copy.qualifiedDays,
                    value: '${stats.qualifiedDays}',
                    unit: copy.qualifiedDaysUnit,
                    color: colors.brandAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _Stat(
                    label: copy.qualifiedRate,
                    value: stats.qualifiedRate == null
                        ? '—'
                        : (stats.qualifiedRate! * 100).toStringAsFixed(0),
                    unit: stats.qualifiedRate == null ? null : '%',
                    color: colors.ringStand,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: copy.longest,
                    value: stats.longestSingleHours == null
                        ? '—'
                        : stats.longestSingleHours!.toStringAsFixed(1),
                    unit: stats.longestSingleHours == null
                        ? null
                        : copy.longestUnit,
                    color: colors.chartPurple,
                  ),
                ),
              ],
            ),
            if (stats.avgQualifiedHours != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s3),
              Text(
                '${copy.avgQualified} '
                '${stats.avgQualifiedHours!.toStringAsFixed(1)} '
                '${copy.longestUnit}',
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ],
            if (stats.firstRecordDate != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s1),
              Text(
                copy.since(date: stats.firstRecordDate!),
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 单个统计格：色点标签 + 大数字 + 单位。
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Semantics(
      label: '$label $value ${unit ?? ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: textStyles.text3xl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
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
        ],
      ),
    );
  }
}

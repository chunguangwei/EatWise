import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/settings/domain/bmi.dart';
import 'package:flutter/material.dart';

/// 身体档案页 BMI 卡（薄荷走查 P1，对标薄荷健康档案「BMI 区间条 + 徽标」）：
/// 数值 + 区间条（偏低/标准/偏高/肥胖，中国成人标准 WS/T 428-2013）+
/// 状态徽标。缺身高或体重时显示补全引导文案。
///
/// 颜色语义：徽标标准=绿、其余=黄（橙色系无 token，黄色最接近）；区间条
/// 肥胖段用红色——红色只表警告语义（§3.3），肥胖段正是需要警示的区间。
///
/// 存量异常兜底：BMI > 35 时追加「体重单位是公斤」提示行——早期用户可能
/// 按斤填了体重（如 170 斤填成 170 kg），BMI 会虚高到非人生理区间。
class BmiCard extends StatelessWidget {
  const BmiCard({super.key, this.heightCm, this.weightKg});

  /// 身高（cm）；与 [weightKg] 齐备才展示区间条。
  final double? heightCm;

  /// 体重（kg）。
  final double? weightKg;

  /// 区间条展示窗口（BMI 14–32，覆盖四段且两端留余量）。
  static const double _barMin = 14;
  static const double _barMax = 32;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final bmiT = t.settings.bodyProfile.bmi;

    final height = heightCm;
    final weight = weightKg;
    final bmi = height != null && height > 0 && weight != null && weight > 0
        ? computeBmi(heightCm: height, weightKg: weight)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      child: bmi == null
          ? Row(
              children: <Widget>[
                Icon(
                  Icons.monitor_weight_outlined,
                  color: colors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    bmiT.missing,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          : _BmiBody(bmi: bmi),
    );
  }
}

class _BmiBody extends StatelessWidget {
  const _BmiBody({required this.bmi});

  final double bmi;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final bmiT = t.settings.bodyProfile.bmi;

    final zone = classifyBmi(bmi);
    final (zoneColor, zoneLabel) = switch (zone) {
      BmiZone.normal => (colors.signalGreen, bmiT.normal),
      BmiZone.underweight => (colors.signalYellow, bmiT.underweight),
      BmiZone.overweight => (colors.signalYellow, bmiT.overweight),
      BmiZone.obese => (colors.signalYellow, bmiT.obese),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(bmiT.title, style: textStyles.textSm),
            const SizedBox(width: AppSpacing.s2),
            Text(
              bmi.toStringAsFixed(1),
              style: textStyles.textXl.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.s2),
            // 状态徽标（颜色 + 文字双编码）。
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              decoration: BoxDecoration(
                color: zoneColor.withValues(alpha: 0.15),
                borderRadius: radii.rSm,
              ),
              child: Text(
                zoneLabel,
                style: textStyles.textXs.copyWith(color: zoneColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        Semantics(
          label: '${bmiT.title} ${bmi.toStringAsFixed(1)} $zoneLabel',
          child: LayoutBuilder(
            builder: (context, constraints) {
              const window = BmiCard._barMax - BmiCard._barMin;
              final fraction = ((bmi - BmiCard._barMin) / window).clamp(
                0.0,
                1.0,
              );
              return SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      top: 3,
                      bottom: 3,
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          children: <Widget>[
                            // 段宽 ∝ 区间跨度：14–18.5 / 18.5–24 / 24–28 / 28–32。
                            Expanded(
                              flex: 45,
                              child: ColoredBox(
                                color: colors.signalYellow.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 55,
                              child: ColoredBox(
                                color: colors.signalGreen.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 40,
                              child: ColoredBox(
                                color: colors.signalYellow.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 40,
                              child: ColoredBox(
                                color: colors.signalRed.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: fraction * constraints.maxWidth - 1.5,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: colors.textPrimary,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        // 区间分界刻度（中国成人标准 WS/T 428-2013，位置按条窗口比例对齐）。
        SizedBox(
          height: 16,
          child: Stack(
            children: <Widget>[
              for (final tick in <double>[18.5, 24, 28])
                Align(
                  alignment: Alignment(
                    ((tick - BmiCard._barMin) /
                                (BmiCard._barMax - BmiCard._barMin)) *
                            2 -
                        1,
                    0,
                  ),
                  child: Text(
                    tick % 1 == 0 ? tick.toInt().toString() : '$tick',
                    style: textStyles.textXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 存量异常兜底：BMI > 35 大概率是「按斤填了体重」（输入处已有单位
        // 切换，这行仅作存量数据提醒）。
        if (bmi > 35) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colors.signalYellow,
              ),
              const SizedBox(width: AppSpacing.s1),
              Expanded(
                child: Text(
                  bmiT.unitHint,
                  style: textStyles.textXs.copyWith(color: colors.signalYellow),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/domain/exercise_goals.dart';
import 'package:eatwise/features/health/domain/health_activity.dart';
import 'package:flutter/material.dart';

/// 运动数据同步单独同意弹窗（GDPR Art.9 / PIPL §29 explicit consent，
/// 合规 §2）：首次开启「同步运动数据」前弹出，明示采集范围（步数/活动
/// 能量/体重）、用途（仅展示热量消耗）、本地处理不出端、可随时关闭。
///
/// 返回 true = 用户同意；false/null = 不同意或 dismiss（均视为未同意）。
Future<bool> showExerciseSyncConsentDialog(BuildContext context) async {
  final t = Translations.of(context);
  final colors = Theme.of(context).extension<AppColors>()!;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.settings.health.consentTitle),
      content: Text(t.settings.health.consentBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(t.settings.health.consentDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: colors.brandPrimary),
          child: Text(t.settings.health.consentAgree),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 数据页「今日消耗」卡（阶段 D）：活动能量 + 步数 + 摄入−消耗结余。
///
/// 薄荷走查 P2 升级：[burnGoalKcal] 非空时展示消耗目标环（X/目标 Y 千卡，
/// 对标薄荷运动页），[stepsGoal] 非空时步数行附「X/目标 步」进度文本。
/// 目标为纯展示口径（本地偏好），不占信号灯语义色、不参与判定。
///
/// 仅在同步已开启且读取就绪时由数据页挂载；UI 只做接线，换算与结余
/// 口径见 `features/health/domain/health_activity.dart`。
class TodayBurnCard extends StatelessWidget {
  const TodayBurnCard({
    super.key,
    required this.steps,
    required this.burnKcal,
    required this.estimated,
    this.intakeKcal,
    this.burnGoalKcal,
    this.stepsGoal,
    this.stepsGuide,
  });

  /// 今日步数（null = 无数据/设备不支持，展示「—」）。
  final int? steps;

  /// 活动消耗（kcal；系统活动能量或步数粗估兜底 + 手动运动合计的合并值）。
  final double? burnKcal;

  /// burnKcal 是否来自步数粗估（true 时标注「估算」）。
  final bool estimated;

  /// 当日摄入（kcal；非空且有消耗时展示结余行）。
  final double? intakeKcal;

  /// 每日消耗目标（kcal；null = 不展示目标环）。
  final double? burnGoalKcal;

  /// 每日步数目标（步；null = 不展示步数进度行）。
  final int? stepsGoal;

  /// 步数「—」时的引导文案（无 GMS 设备：「手动记运动可计入消耗」）。
  final String? stepsGuide;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final burnText = burnKcal == null
        ? '—'
        : estimated
        ? t.nutrition.data.burn.estimatedValue(
            kcal: burnKcal!.toStringAsFixed(0),
          )
        : t.nutrition.data.burn.kcalValue(kcal: burnKcal!.toStringAsFixed(0));
    final balance = (burnKcal != null && intakeKcal != null)
        ? energyBalanceKcal(intakeKcal: intakeKcal!, burnKcal: burnKcal!)
        : null;
    final burnGoal = burnGoalKcal;
    final stepGoal = stepsGoal;
    final showGoalRing = burnGoal != null && burnKcal != null;
    final showStepsProgress = stepGoal != null && steps != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.nutrition.data.burn.title,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              if (showGoalRing) ...<Widget>[
                _BurnGoalRing(burnKcal: burnKcal!, goalKcal: burnGoal),
                const SizedBox(width: AppSpacing.s4),
              ],
              Expanded(
                child: _Metric(
                  label: t.nutrition.data.burn.activeEnergy,
                  value: burnText,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Metric(
                      label: t.nutrition.data.burn.steps,
                      value: steps?.toString() ?? '—',
                    ),
                    if (showStepsProgress) ...<Widget>[
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        t.nutrition.data.burn.stepsGoalProgress(
                          steps: '${steps!}',
                          goal: '$stepGoal',
                        ),
                        style: textStyles.textXs.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    // 无 GMS 设备（步数「—」）→ 引导手动记运动计入消耗。
                    if (steps == null && stepsGuide != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        stepsGuide!,
                        style: textStyles.textXs.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (balance != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.nutrition.data.burn.balance(kcal: _signedKcal(balance)),
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  /// 结余带符号（+120 / -80 kcal，正盈余负缺口）。
  static String _signedKcal(double kcal) {
    final rounded = kcal.toStringAsFixed(0);
    return kcal >= 0 ? '+$rounded' : rounded;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          value,
          style: textStyles.textXl.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

/// 消耗目标环（薄荷走查 P2）：中心百分比 + 环下「X / 目标 Y 千卡」。
///
/// 画法参考断食计时环（fasting_ring.dart）：12 点起笔 conic 弧、圆头收尾；
/// 弧色固定 brandPrimary（目标进度非判定结果，不占信号灯语义色）。
class _BurnGoalRing extends StatelessWidget {
  const _BurnGoalRing({required this.burnKcal, required this.goalKcal});

  final double burnKcal;
  final double goalKcal;

  static const double _size = 88;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final progress = exerciseGoalProgress(value: burnKcal, goal: goalKcal);
    final percent =
        (exerciseGoalProgress(value: burnKcal, goal: goalKcal) * 100).round();

    return Semantics(
      label: t.nutrition.data.burn.goalRingLabel(percent: '$percent'),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: _size,
            height: _size,
            child: CustomPaint(
              painter: _GoalRingPainter(
                progress: progress,
                arcColor: colors.brandPrimary,
                trackColor: colors.border.withValues(alpha: 0.2),
              ),
              child: Center(
                child: Text(
                  '$percent%',
                  style: textStyles.textLg.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            t.nutrition.data.burn.goalProgress(
              kcal: burnKcal.toStringAsFixed(0),
              goal: goalKcal.toStringAsFixed(0),
            ),
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 目标环画笔（与断食计时环同构：底环 + 12 点起笔进度弧）。
class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({
    required this.progress,
    required this.arcColor,
    required this.trackColor,
  });

  final double progress;
  final Color arcColor;
  final Color trackColor;

  static const double _strokeWidth = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = trackColor,
    );

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * clamped,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = arcColor,
      );
    }
  }

  @override
  bool shouldRepaint(_GoalRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.arcColor != arcColor ||
        oldDelegate.trackColor != trackColor;
  }
}

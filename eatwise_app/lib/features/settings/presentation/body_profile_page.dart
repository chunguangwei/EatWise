import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_error_text.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/body_profile_form.dart';
import 'package:eatwise/features/account/presentation/weight_goal_fields.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/settings/application/body_profile_service.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/domain/profile_completeness.dart';
import 'package:eatwise/features/settings/presentation/bmi_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「我的-身体档案」页（阶段 A：查看/修改性别/出生年/身高/体重/活动水平；
/// 阶段 B：目标体重/目标日期编辑，可清空）。
/// 保存即重算当日营养目标（D-04 + 缺口法，历史不回溯）；
/// 登录态同步 PATCH /users/me（U2）。
class BodyProfilePage extends ConsumerStatefulWidget {
  const BodyProfilePage({super.key});

  @override
  ConsumerState<BodyProfilePage> createState() => _BodyProfilePageState();
}

class _BodyProfilePageState extends ConsumerState<BodyProfilePage> {
  OnboardingProfile _profile = OnboardingProfile.empty;
  double? _targetWeightKg;
  LocalDate? _targetDate;
  bool _valid = true;
  bool _goalValid = true;
  bool _saving = false;

  /// 用户是否已改动表单（完善度进度条口径：未改动按服务端/本地初值，
  /// 改动后按当前表单值实时联动）。
  bool _edited = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final nowUtc = ref.read(nowUtcProvider);
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      nowUtc * 1000,
      isUtc: true,
    ).year;
    final today = localDateOf(nowUtc, ref.read(deviceLocationProvider));
    // 等 U1 就绪再建表单：本地无档案时可用服务端档案预填（失败/未登录
    // userMeProvider 回落 null，同样视为就绪）。
    final me = ref.watch(userMeProvider);
    // 表单初值（本地档案优先，回落服务端档案）；完善度进度条与表单共用。
    final initial = me.hasValue
        ? ref.read(bodyProfileServiceProvider).initialProfile(me.value)
        : OnboardingProfile.empty;
    // 档案完善度（薄荷走查 P3）：未改动按初值，改动后随表单实时联动。
    final effective = _edited
        ? _profile.copyWith(
            targetWeightKg: () => _targetWeightKg,
            targetDate: () => _targetDate,
          )
        : initial;
    final completeness = profileCompletenessPercent(effective);

    return Scaffold(
      appBar: AppBar(title: Text(t.settings.bodyProfile.title)),
      body: SafeArea(
        child: !me.hasValue
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.s4),
                children: <Widget>[
                  // D-18：敏感信息明示用途与留空兜底口径。
                  Text(
                    t.onboarding.profile.subtitle,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  // 完善度进度条（P3：游戏化补齐引导；100% 时 Offstage 隐藏
                  // 不占位——保持 ListView 子树结构稳定，表单 State 不重建）。
                  Offstage(
                    offstage: completeness >= 100,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
                      child: Row(
                        children: <Widget>[
                          Text(
                            t.settings.bodyProfile.completeness(
                              percent: completeness,
                            ),
                            style: textStyles.textSm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: completeness / 100,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                              color: colors.brandPrimary,
                              backgroundColor: colors.border.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  // BMI 卡（P1）：随表单输入实时联动；缺身高/体重走补全引导。
                  BmiCard(
                    heightCm: _profile.heightCm,
                    weightKg: _profile.weightKg,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Builder(
                    builder: (context) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          BodyProfileForm(
                            currentYear: currentYear,
                            initial: initial,
                            onChanged: (profile, valid) {
                              // 总是 setState：BMI 卡随输入实时刷新。
                              setState(() {
                                _profile = profile;
                                _valid = valid;
                                _edited = true;
                              });
                            },
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          // 阶段 B：减重目标（仅减脂目标生效；可留空/清空）。
                          Text(
                            t.settings.bodyProfile.goalSection,
                            style: textStyles.textSm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          WeightGoalFields(
                            today: today,
                            initialWeightKg: initial.targetWeightKg,
                            initialDate: initial.targetDate,
                            onChanged: (weightKg, date, valid) {
                              _targetWeightKg = weightKg;
                              _targetDate = date;
                              // 目标字段变化同样驱动完善度进度条联动。
                              setState(() => _edited = true);
                              if (valid != _goalValid) {
                                setState(() => _goalValid = valid);
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  FilledButton(
                    key: const ValueKey<String>('settings.bodyProfile.save'),
                    onPressed: !_valid || !_goalValid || _saving
                        ? null
                        : () => _save(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                      minimumSize: const Size.fromHeight(AppSpacing.s12),
                    ),
                    child: Text(t.settings.bodyProfile.save),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final t = Translations.of(context);
    setState(() => _saving = true);
    try {
      final goal = await ref
          .read(bodyProfileServiceProvider)
          .save(
            _profile.copyWith(
              targetWeightKg: () => _targetWeightKg,
              targetDate: () => _targetDate,
            ),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // 兜底口径下不展示具体 kcal（默认估算），精准计算才展示新目标。
            goal.usedFallback
                ? t.settings.bodyProfile.saved
                : t.settings.bodyProfile.goalUpdated(kcal: goal.targetKcal),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(apiErrorDisplayMessage(t, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

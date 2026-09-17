import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_error_text.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/body_profile_form.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/settings/application/body_profile_service.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「我的-身体档案」页（阶段 A）：查看/修改性别/出生年/身高/体重/活动水平，
/// 保存即重算当日营养目标（D-04）；登录态同步 PATCH /users/me（U2）。
class BodyProfilePage extends ConsumerStatefulWidget {
  const BodyProfilePage({super.key});

  @override
  ConsumerState<BodyProfilePage> createState() => _BodyProfilePageState();
}

class _BodyProfilePageState extends ConsumerState<BodyProfilePage> {
  OnboardingProfile _profile = OnboardingProfile.empty;
  bool _valid = true;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      ref.read(nowUtcProvider) * 1000,
      isUtc: true,
    ).year;
    // 等 U1 就绪再建表单：本地无档案时可用服务端档案预填（失败/未登录
    // userMeProvider 回落 null，同样视为就绪）。
    final me = ref.watch(userMeProvider);

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
                  const SizedBox(height: AppSpacing.s4),
                  BodyProfileForm(
                    currentYear: currentYear,
                    initial: ref
                        .read(bodyProfileServiceProvider)
                        .initialProfile(me.value),
                    onChanged: (profile, valid) {
                      _profile = profile;
                      if (valid != _valid) setState(() => _valid = valid);
                    },
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  FilledButton(
                    key: const ValueKey<String>('settings.bodyProfile.save'),
                    onPressed: !_valid || _saving ? null : () => _save(context),
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
      final goal = await ref.read(bodyProfileServiceProvider).save(_profile);
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

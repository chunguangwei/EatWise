import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 首次启动隐私弹窗页（合规 §4.1，路由 /legal/consent）。
///
/// 结构：主同意（必勾，不勾不能继续）+ 健康数据敏感个人信息处理
/// 单独同意（PIPL §29，独立勾选、默认不勾、不捆绑）；附「非医疗建议」
/// 免责摘要与特殊人群提示入口。拒绝主政策 → 退出 App；仅拒绝健康数据
/// 单独同意 → 可继续使用（营养目标走默认值，D-04）。
class PrivacyConsentPage extends ConsumerStatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  ConsumerState<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends ConsumerState<PrivacyConsentPage> {
  bool _mainAgreed = false;
  bool _healthAgreed = false;
  bool _submitting = false;

  Future<void> _agree() async {
    if (!_mainAgreed || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(privacyConsentControllerProvider.notifier)
          .agree(healthDataGranted: _healthAgreed);
      // 埋点授权默认跟随主同意（合规 §4.4 产品改进计划默认开启可关
      // 〔待外部确认：法务〕；弹窗完成前 ConsentStore 缺省 false，
      // AnalyticsService 全程 suppressed）。
      await ref
          .read(analyticsServiceProvider)
          .setAnalyticsConsent(true, consentType: 'privacy_dialog');
    } on Object {
      // 落盘失败：复位提交态允许重试（原实现无复位路径，按钮永久置灰）。
      if (mounted) setState(() => _submitting = false);
      return;
    }
    // 显式导航离开授权页：不能依赖门禁翻转后的隐式 redirect——未登录新
    // 用户停留在 /legal/consent 时 redirect 因 /legal/* 放行规则返回
    // null，页面永不跳转（v1.1.1 走查 R1 卡死）。go('/') 后由 redirect
    // 按登录/引导门禁分流（/login、/onboarding 或首页）。
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s8),
            Text(
              t.legal.consent.title,
              style: textStyles.textXl,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              t.legal.consent.summary,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 协议全文入口（门禁放行 /legal/* 前缀，同意前可阅读）。
            TextButton(
              onPressed: () => context.push('/legal/privacy'),
              child: Text(t.legal.consent.viewPrivacyPolicy),
            ),
            TextButton(
              onPressed: () => context.push('/legal/agreement'),
              child: Text(t.legal.consent.viewUserAgreement),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 「非医疗建议」免责摘要（§5.1 常驻位之一）+ 特殊人群入口（§5.2）。
            Container(
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                borderRadius: radii.rMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.legal.consent.disclaimerSummary,
                    style: textStyles.textSm.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/legal/disclaimer'),
                    child: Text(t.legal.consent.specialGroupsEntry),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            // ① 主同意（必勾）。
            _ConsentCheckRow(
              checked: _mainAgreed,
              onChanged: (value) =>
                  setState(() => _mainAgreed = value ?? false),
              child: Text(
                t.legal.consent.agreeMain,
                style: textStyles.textBase.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // ② 健康数据单独同意（独立勾选，默认不勾）。
            _ConsentCheckRow(
              checked: _healthAgreed,
              onChanged: (value) =>
                  setState(() => _healthAgreed = value ?? false),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.legal.consent.healthTitle,
                    style: textStyles.textBase.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    t.legal.consent.healthBody,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: _mainAgreed && !_submitting ? _agree : null,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                t.legal.consent.agreeAndContinue,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
            // 拒绝主政策 → 退出 App（§4.1 拒绝路径）。
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: Text(
                t.legal.consent.decline,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 勾选行（触控区 ≥44px；点击整行翻转勾选）。
class _ConsentCheckRow extends StatelessWidget {
  const _ConsentCheckRow({
    required this.checked,
    required this.onChanged,
    required this.child,
  });

  final bool checked;
  final ValueChanged<bool?> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(value: checked, onChanged: onChanged),
            const SizedBox(width: AppSpacing.s1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 协议正文页（隐私政策 / 用户协议通用，中英双语全文走 i18n key，
/// 内容按合规 §2 收集清单 / §6 SDK 清单 / §7 数据安全写实，
/// 文首标注〔待外部确认：法务终稿〕）。
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Text(
            body,
            style: textStyles.textSm.copyWith(color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// 「非医疗建议」免责声明 + 9 类特殊人群提示独立页（合规 §5，
/// 设置页常驻入口 + 首启弹窗特殊人群入口共用）。
class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.legal.disclaimer.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            Text(t.legal.disclaimer.notMedicalTitle, style: textStyles.textXl),
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.legal.disclaimer.notMedicalBody,
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              t.legal.disclaimer.specialGroupsTitle,
              style: textStyles.textXl,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.legal.disclaimer.specialGroupsBody,
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              t.legal.draftNote,
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

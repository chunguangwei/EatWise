import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// M0 基建演示页：验证 Token 主题与中英双语可用（非真实页面）。
class DemoHomeScreen extends StatelessWidget {
  const DemoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;

    return Scaffold(
      appBar: AppBar(title: Text(t.fasting.home.title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        children: <Widget>[
          Text(t.fasting.home.stateFasting, style: textStyles.textH1),
          const SizedBox(height: AppSpacing.s2),
          Text(
            t.fasting.home.attribution(date: '7月28日'),
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s6),
          // 信号灯三色（语义固定：绿=达标 / 黄=提醒 / 红=警示）
          Row(
            children: <Widget>[
              _ColorChip(color: colors.signalGreen, label: 'signalGreen'),
              const SizedBox(width: AppSpacing.s2),
              _ColorChip(color: colors.signalYellow, label: 'signalYellow'),
              const SizedBox(width: AppSpacing.s2),
              _ColorChip(color: colors.signalRed, label: 'signalRed'),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          // 卡片：圆角 + 阴影 Token
          Container(
            padding: const EdgeInsets.all(AppSpacing.s4),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: radii.rLg,
              boxShadow: shadows.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('12:34:56', style: textStyles.textTimer),
                const SizedBox(height: AppSpacing.s2),
                Text(t.record.empty.title, style: textStyles.textBase),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          // CTA：品牌主色 / 暖阳橙
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
            child: Text(t.fasting.home.endFast, style: textStyles.textBase),
          ),
          const SizedBox(height: AppSpacing.s2),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandAccent,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
            child: Text(t.fasting.home.extend, style: textStyles.textBase),
          ),
          const SizedBox(height: AppSpacing.s8),
          // 语言切换示例（D-15：即时生效，无需重启）
          Text(t.settings.language.title, style: textStyles.textXl),
          const SizedBox(height: AppSpacing.s2),
          Wrap(
            spacing: AppSpacing.s2,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => LocaleSettings.useDeviceLocale(),
                child: Text(t.settings.language.system),
              ),
              OutlinedButton(
                onPressed: () => LocaleSettings.setLocale(AppLocale.zhCn),
                child: Text(t.settings.language.zhCN),
              ),
              OutlinedButton(
                onPressed: () => LocaleSettings.setLocale(AppLocale.en),
                child: Text(t.settings.language.en),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      width: 88,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: radii.rSm),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}

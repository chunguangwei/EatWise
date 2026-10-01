import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 页面级空态/错误态统一组件（v1.16.0 全局设计感优化——规格取自社区
/// feed 的 _CenteredMessage，各页四档图标/三档标题/混用 CTA 的散装空态
/// 全部收敛到这一个组件）。
///
/// 规格：64px 图标（次要色）→ textXl 主文案 → textSm 副文案（可选）→
/// 48px FilledButton CTA（可选，主题默认样式）。置于可滚动 ListView
/// 中（短内容页下拉刷新/小屏不溢出）。
class AppStateView extends StatelessWidget {
  const AppStateView({
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
    super.key,
  });

  /// 顶部插画图标（建议 rounded 系，64px）。
  final IconData icon;

  /// 主文案（textXl 居中）。
  final String title;

  /// 副文案（textSm 次要色居中；可空）。
  final String? subtitle;

  /// CTA 文案（与 [onCta] 成对提供；均空则不渲染按钮）。
  final String? ctaLabel;

  /// CTA 回调。
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return ListView(
      // 短内容也可拖动（外层 RefreshIndicator 下拉刷新依赖可滚动手势）。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.s4),
      children: <Widget>[
        const SizedBox(height: AppSpacing.s16),
        Icon(icon, size: 64, color: colors.textSecondary),
        const SizedBox(height: AppSpacing.s4),
        Text(title, style: textStyles.textXl, textAlign: TextAlign.center),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Text(
            subtitle!,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (ctaLabel != null && onCta != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s6),
          Center(
            child: FilledButton(onPressed: onCta, child: Text(ctaLabel!)),
          ),
        ],
      ],
    );
  }
}

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 带提交中态的主按钮（2026-10-15 走查修复：登录中按钮「全白色看不清」）。
///
/// 根因：忙时 `onPressed: null` 进禁用态（浅灰底 fillSubtle），而按钮文字
/// 又强制白色，白字压近白底直接隐形。本组件忙时保持动作色与高对比前景，
/// 用迷你转圈表达在途状态。
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  /// 常态文案（如「登录」）。
  final String label;

  /// 提交中文案（如「登录中…」）。
  final String busyLabel;

  /// 是否提交中（禁用点击 + 转圈）。
  final bool busy;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colors.actionPrimary,
        foregroundColor: colors.onActionPrimary,
        disabledBackgroundColor: colors.actionPrimary,
        disabledForegroundColor: colors.onActionPrimary,
        minimumSize: const Size.fromHeight(AppSpacing.s12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (busy) ...<Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onActionPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
          ],
          Text(
            busy ? busyLabel : label,
            style: textStyles.textBase.copyWith(color: colors.onActionPrimary),
          ),
        ],
      ),
    );
  }
}

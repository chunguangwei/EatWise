import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/auth_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 修改密码页（R3：旧密码 + 新密码 + 确认新密码）。
///
/// 成功后服务端已吊销全部 refresh token（契约 R3），本地会话被
/// AuthController.changePassword 清除并翻转门禁 → 路由强制回 /login；
/// 本页只负责成功提示，不做手动导航。
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 客户端先校验再发请求：新密码强度（8-64 位含字母数字）+ 两次一致。
  bool _validate() {
    final t = Translations.of(context);
    if (_oldController.text.isEmpty) {
      _showError(t.auth.changePassword.oldRequired);
      return false;
    }
    final newPassword = _newController.text;
    if (newPassword.length < 8 ||
        newPassword.length > 64 ||
        !RegExp(r'[A-Za-z]').hasMatch(newPassword) ||
        !RegExp(r'\d').hasMatch(newPassword)) {
      _showError(t.auth.error.passwordTooWeak);
      return false;
    }
    if (_confirmController.text != newPassword) {
      _showError(t.auth.changePassword.passwordMismatch);
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(
            oldPassword: _oldController.text,
            newPassword: _newController.text,
          );
    } on ApiException {
      // 错误文案经 authControllerProvider.state 展示。
      return;
    }
    if (!mounted) return;
    // 成功：全部 refresh token 已吊销 → 本地清会话回登录页。
    // 门禁翻转触发 GoRouter redirect 回 /login，此处仅提示。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.of(context).auth.changePassword.success),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final authState = ref.watch(authControllerProvider);
    final errorText = authErrorMessage(t, authState);
    final busy = authState.changingPassword;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.auth.changePassword.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s6),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.changePassword.oldLabel,
              hint: t.auth.changePassword.oldHint,
              controller: _oldController,
              obscureText: _obscureOld,
              onToggleObscure: () => setState(() => _obscureOld = !_obscureOld),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(64),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.changePassword.newLabel,
              hint: t.auth.changePassword.newHint,
              controller: _newController,
              obscureText: _obscureNew,
              onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(64),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.changePassword.confirmLabel,
              hint: t.auth.changePassword.confirmHint,
              controller: _confirmController,
              obscureText: _obscureConfirm,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(64),
              ],
            ),
            if (errorText != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s3),
              Text(
                errorText,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                authState.changingPassword
                    ? t.auth.changePassword.submitting
                    : t.auth.changePassword.submit,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required AppColors colors,
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: colors.bgSecondary,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s2),
        borderSide: BorderSide(color: colors.border.withValues(alpha: 0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s2),
        borderSide: BorderSide(color: colors.border.withValues(alpha: 0.4)),
      ),
      // 绿 focus 描边（设计稿表单规范）。
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s2),
        borderSide: BorderSide(color: colors.brandPrimary, width: 2),
      ),
    );
  }

  Widget _buildField({
    required Translations t,
    required AppColors colors,
    required AppTextStyles textStyles,
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: AppSpacing.s12, // 48px 输入框
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: TextInputType.visiblePassword,
            inputFormatters: inputFormatters,
            decoration: _fieldDecoration(
              colors: colors,
              hint: hint,
              suffix: onToggleObscure == null
                  ? null
                  : IconButton(
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
            ).copyWith(counterText: ''),
          ),
        ),
      ],
    );
  }
}

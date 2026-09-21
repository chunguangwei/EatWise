import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/auth_error.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/settings/application/settings_prefs_sync.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 注册页（R1：用户名+密码，注册成功即自动登录）。
///
/// 表单规范同登录页：48px 输入框、绿 focus 描边、触控区 ≥44px（D-15）。
/// 成功后由路由门禁自动跳转（/onboarding 或首页），本页不手动导航。
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreed = false;
  int _passwordStrengthValue = 0;

  /// 用户名：3-20 位字母/数字/下划线（契约 R1）。
  static final RegExp _username = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    // 共享 AuthState：进入注册页清掉上一页残留的失败文案。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).clearError();
    });
  }

  void _onPasswordChanged() {
    setState(
      () =>
          _passwordStrengthValue = _passwordStrength(_passwordController.text),
    );
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 客户端先校验再发请求：用户名格式 + 密码强度（8-64 位含字母数字）
  /// + 两次输入一致 + 协议勾选。
  bool _validate() {
    final t = Translations.of(context);
    if (!_username.hasMatch(_usernameController.text.trim())) {
      _showError(t.auth.register.invalidUsername);
      return false;
    }
    final password = _passwordController.text;
    if (password.length < 8 ||
        password.length > 64 ||
        !RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      _showError(t.auth.error.passwordTooWeak);
      return false;
    }
    if (_confirmController.text != password) {
      _showError(t.auth.register.passwordMismatch);
      return false;
    }
    if (!_agreed) {
      _showError(t.auth.register.agreeRequired);
      return false;
    }
    return true;
  }

  Future<void> _register() async {
    if (!_validate()) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
      _onRegisterSuccess();
    } on ApiException {
      // 错误文案经 authControllerProvider.state 展示。
    }
  }

  /// 注册成功（已自动登录）收尾：撤销删除提示 + 触发一轮同步（§2.1）。
  void _onRegisterSuccess() {
    final t = Translations.of(context);
    if (ref.read(authControllerProvider).deletionCancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.account.deletionCancelled)),
      );
    }
    try {
      unawaited(ref.read(recordSyncEngineProvider).syncNow());
    } on Object {
      // 防御：同步引擎未装配（如测试环境仅注入认证栈）时跳过。
    }
    // D-21：注册即登录，下行用户级偏好（失败静默）。
    try {
      unawaited(ref.read(settingsPrefsSyncProvider).pull());
    } on Object {
      // 防御：偏好同步未装配时跳过。
    }
    // 重装/换机恢复：本地无生效方案时下行回填服务端当前方案（失败静默）。
    try {
      unawaited(ref.read(fastingPlanSyncProvider)?.pull());
    } on Object {
      // 防御：方案同步未装配时跳过。
    }
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
    final busy = authState.registering || authState.loggingIn;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        // 顶部返回按钮（路由 push 进入，自动出现）。
        title: Text(t.auth.register.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s8),
            Text(
              t.auth.register.subtitle,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s6),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.register.usernameLabel,
              hint: t.auth.register.usernameHint,
              controller: _usernameController,
              keyboardType: TextInputType.text,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                LengthLimitingTextInputFormatter(20),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.register.passwordLabel,
              hint: t.auth.register.passwordHint,
              controller: _passwordController,
              obscureText: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(64),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _buildField(
              t: t,
              colors: colors,
              textStyles: textStyles,
              label: t.auth.register.confirmPasswordLabel,
              hint: t.auth.register.confirmPasswordHint,
              controller: _confirmController,
              obscureText: _obscureConfirm,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              keyboardType: TextInputType.visiblePassword,
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
            const SizedBox(height: AppSpacing.s3),
            _buildPasswordStrength(t, colors, textStyles),
            const SizedBox(height: AppSpacing.s4),
            _buildAgreementRow(t, colors, textStyles),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: busy ? null : _register,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                authState.registering
                    ? t.auth.register.registering
                    : t.auth.register.register,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordStrength(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
  ) {
    final strength = _passwordStrengthValue;
    if (strength == 0) {
      // 空密码不展示；不足 8 位尚无强度评级，只给长度提示
      // （直接取 labels[strength-1] 会越界崩溃）。
      if (_passwordController.text.isEmpty) return const SizedBox.shrink();
      return Text(
        t.auth.register.strengthTooShort,
        style: textStyles.textXs.copyWith(color: colors.signalRed),
      );
    }
    final labels = [
      t.auth.register.strengthWeak,
      t.auth.register.strengthMedium,
      t.auth.register.strengthStrong,
    ];
    final barColors = [
      colors.signalRed,
      colors.signalYellow,
      colors.signalGreen,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < strength
                        ? barColors[strength - 1]
                        : colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          labels[strength - 1],
          style: textStyles.textXs.copyWith(color: barColors[strength - 1]),
        ),
      ],
    );
  }

  /// 密码强度：1=弱（长度≥8），2=中（含字母+数字+特殊字符），3=强（≥12位且含三类）。
  int _passwordStrength(String password) {
    if (password.length < 8) return 0;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(password);
    if (password.length >= 12 && hasLetter && hasDigit && hasSpecial) return 3;
    if (hasLetter && hasDigit && hasSpecial) return 2;
    return 1;
  }

  Widget _buildAgreementRow(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            activeColor: colors.brandPrimary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: RichText(
              text: TextSpan(
                style: textStyles.textSm.copyWith(color: colors.textPrimary),
                children: <TextSpan>[
                  TextSpan(text: t.auth.register.agreePrefix),
                  TextSpan(
                    text: t.legal.privacyPolicy.title,
                    style: TextStyle(
                      color: colors.brandPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => context.push('/legal/privacy'),
                  ),
                  TextSpan(text: t.auth.register.agreeAnd),
                  TextSpan(
                    text: t.legal.userAgreement.title,
                    style: TextStyle(
                      color: colors.brandPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => context.push('/legal/agreement'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
    TextInputType? keyboardType,
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
            keyboardType: keyboardType,
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

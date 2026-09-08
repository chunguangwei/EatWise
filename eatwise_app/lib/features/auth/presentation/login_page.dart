import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/presentation/auth_error.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 账号密码登录页（R2 主登录方式）。
///
/// 表单规范：48px 输入框、绿 focus 描边、触控区 ≥44px、中英双语（D-15）。
/// 手机号验证码登录（A2）保留为「其他登录方式」折叠区，备用降级。
/// 登录成功后由路由门禁自动跳转（/onboarding 或首页），本页不手动导航。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  Timer? _countdownTimer;
  int _countdown = 0;

  bool _obscurePassword = true;

  /// 「其他登录方式」（手机验证码）折叠区是否展开。
  bool _altMethodsExpanded = false;

  /// 用户名：3-20 位字母/数字/下划线（契约 R1）。
  static final RegExp _username = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 客户端先校验再发请求：用户名格式 + 密码长度。
  bool _validateUsernamePassword() {
    final t = Translations.of(context);
    if (!_username.hasMatch(_usernameController.text.trim())) {
      _showError(t.auth.login.invalidUsername);
      return false;
    }
    final password = _passwordController.text;
    if (password.length < 8 || password.length > 64) {
      _showError(t.auth.login.invalidPassword);
      return false;
    }
    return true;
  }

  Future<void> _login() async {
    if (!_validateUsernamePassword()) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginWithPassword(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
      _onLoginSuccess();
    } on ApiException {
      // 错误文案经 authControllerProvider.state 展示。
    }
  }

  /// 登录成功共用收尾：撤销删除提示 + 触发一轮同步（§2.1）。
  void _onLoginSuccess() {
    final t = Translations.of(context);
    // 冷静期内登录自动撤销删除（合规 §4.3）：明示告知。
    if (ref.read(authControllerProvider).deletionCancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.account.deletionCancelled)),
      );
    }
    // 成功：AuthGate 通知 GoRouter redirect，无需手动跳转；
    // §2.1 登录成功触发一轮同步（先上行 pending 再增量下行）。
    try {
      unawaited(ref.read(recordSyncEngineProvider).syncNow());
    } on Object {
      // 防御：同步引擎未装配（如测试环境仅注入认证栈）时跳过。
    }
  }

  /// 手机号归一化为 E.164：11 位国内号自动补 +86。
  String _normalizedPhone() {
    final raw = _phoneController.text.trim().replaceAll(' ', '');
    if (raw.startsWith('+')) return raw;
    if (raw.startsWith('86') && raw.length == 13) return '+$raw';
    return '+86$raw';
  }

  Future<void> _sendCode() async {
    final t = Translations.of(context);
    final phone = _normalizedPhone();
    if (!_e164.hasMatch(phone)) {
      _showError(t.auth.login.invalidPhone);
      return;
    }
    try {
      final resendAfterSec = await ref
          .read(authControllerProvider.notifier)
          .sendCode(phone);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.auth.login.codeSent)));
      _startCountdown(resendAfterSec);
    } on ApiException {
      // 错误文案经 authControllerProvider.state 展示。
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _countdown = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _loginWithPhone() async {
    final t = Translations.of(context);
    final phone = _normalizedPhone();
    final code = _codeController.text.trim();
    if (!_e164.hasMatch(phone)) {
      _showError(t.auth.login.invalidPhone);
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showError(t.auth.login.invalidCode);
      return;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginWithPhone(phone: phone, code: code);
      _onLoginSuccess();
    } on ApiException {
      // 错误文案经 authControllerProvider.state 展示。
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
    final busy =
        authState.sendingCode || authState.loggingIn || authState.registering;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.auth.login.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s8),
            Text(
              t.auth.login.subtitle,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s6),
            _buildUsernameField(t, colors, textStyles),
            const SizedBox(height: AppSpacing.s4),
            _buildPasswordField(t, colors, textStyles),
            if (errorText != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s3),
              Text(
                errorText,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: busy ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                authState.loggingIn
                    ? t.auth.login.loggingIn
                    : t.auth.login.login,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            // 「没有账号？注册」→ /register。
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  t.auth.login.noAccount,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => context.push('/register'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44), // 触控区 ≥44px
                  ),
                  child: Text(
                    t.auth.login.toRegister,
                    style: textStyles.textSm.copyWith(
                      color: colors.brandPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            // 手机验证码登录降级为折叠的「其他登录方式」（A2 备用）。
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _altMethodsExpanded = !_altMethodsExpanded),
                icon: Icon(
                  _altMethodsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.textSecondary,
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44), // 触控区 ≥44px
                ),
                label: Text(
                  t.auth.login.otherLoginMethods,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_altMethodsExpanded) ...<Widget>[
              const SizedBox(height: AppSpacing.s4),
              _buildPhoneField(t, colors, textStyles),
              const SizedBox(height: AppSpacing.s4),
              _buildCodeField(t, colors, textStyles, busy),
              const SizedBox(height: AppSpacing.s6),
              OutlinedButton(
                onPressed: busy ? null : _loginWithPhone,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(
                  authState.loggingIn
                      ? t.auth.login.loggingIn
                      : t.auth.login.login,
                  style: textStyles.textBase,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                t.auth.login.mockHint,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
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

  Widget _buildUsernameField(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.auth.login.usernameLabel, style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: AppSpacing.s12, // 48px 输入框
          child: TextField(
            controller: _usernameController,
            keyboardType: TextInputType.text,
            autofillHints: const <String>[AutofillHints.username],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: _fieldDecoration(
              colors: colors,
              hint: t.auth.login.usernameHint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.auth.login.passwordLabel, style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: AppSpacing.s12,
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const <String>[AutofillHints.password],
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(64),
            ],
            decoration: _fieldDecoration(
              colors: colors,
              hint: t.auth.login.passwordHint,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
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

  Widget _buildPhoneField(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.auth.login.phoneLabel, style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: AppSpacing.s12, // 48px 输入框
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            decoration: _fieldDecoration(
              colors: colors,
              hint: t.auth.login.phoneHint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeField(
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
    bool busy,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t.auth.login.codeLabel, style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: AppSpacing.s12,
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: _fieldDecoration(
              colors: colors,
              hint: t.auth.login.codeHint,
              suffix: _countdown > 0
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.s2),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          t.auth.login.resendIn(seconds: _countdown),
                          style: textStyles.textSm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : TextButton(
                      onPressed: busy ? null : _sendCode,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44), // 触控区 ≥44px
                      ),
                      child: Text(
                        t.auth.login.sendCode,
                        style: textStyles.textSm.copyWith(
                          color: colors.brandPrimary,
                        ),
                      ),
                    ),
            ).copyWith(counterText: ''),
          ),
        ),
      ],
    );
  }
}

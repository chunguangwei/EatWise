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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 账号密码登录页（R2 唯一登录方式）。
///
/// 表单规范：48px 输入框、绿 focus 描边、触控区 ≥44px、中英双语（D-15）。
/// 手机验证码（A2）能力在 API/Controller 层保留为备用，UI 已隐藏（短信通道未接入）。
/// 登录成功后由路由门禁自动跳转（/onboarding 或首页），本页不手动导航。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;

  /// 用户名：3-20 位字母/数字/下划线（契约 R1）。
  static final RegExp _username = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  @override
  void initState() {
    super.initState();
    // 共享 AuthState：进入登录页清掉上一页残留的失败文案。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
    // D-21：登录成功下行用户级偏好（远端新才覆盖本地，失败静默）。
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
    final busy = authState.loggingIn || authState.registering;

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
}

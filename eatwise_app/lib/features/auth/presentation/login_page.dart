import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 手机号验证码登录页（D-13）。
///
/// 表单规范：48px 输入框、绿 focus 描边、触控区 ≥44px、中英双语（D-15）。
/// 登录成功后由路由门禁自动跳转（/onboarding 或首页），本页不手动导航。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  Timer? _countdownTimer;
  int _countdown = 0;

  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
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

  Future<void> _login() async {
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
          .login(phone: phone, code: code);
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
    final busy = authState.sendingCode || authState.loggingIn;

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
            _buildPhoneField(t, colors, textStyles),
            const SizedBox(height: AppSpacing.s4),
            _buildCodeField(t, colors, textStyles, busy),
            if (authState.errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s3),
              Text(
                authState.errorMessage!,
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
            const SizedBox(height: AppSpacing.s4),
            Text(
              t.auth.login.mockHint,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
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

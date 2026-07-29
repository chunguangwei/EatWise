import 'package:app_settings/app_settings.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/streak/presentation/streak_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 设置页（替换 我的 Tab 占位，M7 + 合规 D-18 落地）。
///
/// 分组卡片列表（设计稿卡片规范，行触控区 ≥44px）：
/// 账号（手机号/登出/删除账号 7 天冷静期）、隐私（协议/导出/健康数据授权/
/// 数据分析授权）、偏好（语言/主题即时生效）、提醒（跳系统通知设置）、
/// 关于（版本/免责声明常驻入口，§5.1）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final authState = ref.watch(authControllerProvider);
    final healthGranted = ref.watch(
      privacyConsentControllerProvider.select((s) => s.healthDataGranted),
    );
    final analyticsGranted = ref.watch(analyticsEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);
    final languageMode = ref.watch(languageModeProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.settings.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            // M5：连胜卡片保留自原 我的 占位页。
            const StreakProfileCard(),
            const SizedBox(height: AppSpacing.s6),
            _SettingsGroup(
              title: t.settings.group.account,
              children: <Widget>[
                // 手机号脱敏展示：服务端 U1 userView 不含 phone 字段
                // （§7.2 字段级加密），暂展示内部 UID〔待外部确认：脱敏口径〕。
                _SettingsTile(
                  title: t.settings.account.phone,
                  trailing: authState.userId ?? t.settings.account.notLoggedIn,
                ),
                _SettingsTile(
                  title: t.settings.account.logout,
                  onTap: () => _confirmLogout(context, ref),
                ),
                _SettingsTile(
                  title: t.settings.account.deleteAccount,
                  titleColor: colors.signalRed,
                  onTap: () => _confirmDeleteAccount(context, ref),
                ),
              ],
            ),
            _SettingsGroup(
              title: t.settings.group.privacy,
              children: <Widget>[
                _SettingsTile(
                  title: t.settings.privacy.privacyPolicy,
                  onTap: () => context.push('/legal/privacy'),
                ),
                _SettingsTile(
                  title: t.settings.privacy.userAgreement,
                  onTap: () => context.push('/legal/agreement'),
                ),
                _SettingsTile(
                  title: t.settings.privacy.exportData,
                  onTap: () => _exportData(context, ref),
                ),
                _SettingsTile(
                  title: t.settings.privacy.healthData,
                  subtitle: t.settings.privacy.healthDataSubtitle,
                  trailingWidget: Switch(
                    value: healthGranted,
                    onChanged: (value) => _setHealthData(context, ref, value),
                  ),
                ),
                _SettingsTile(
                  title: t.settings.privacy.analytics,
                  subtitle: t.settings.privacy.analyticsSubtitle,
                  trailingWidget: Switch(
                    value: analyticsGranted,
                    onChanged: (value) => _setAnalytics(ref, value),
                  ),
                ),
              ],
            ),
            _SettingsGroup(
              title: t.settings.group.preferences,
              children: <Widget>[
                _SettingsTile(
                  title: t.settings.language.title,
                  trailing: _languageLabel(t, languageMode),
                  onTap: () => _pickLanguage(context, ref),
                ),
                _SettingsTile(
                  title: t.settings.theme.title,
                  trailing: _themeLabel(t, themeMode),
                  onTap: () => _pickTheme(context, ref),
                ),
              ],
            ),
            _SettingsGroup(
              title: t.settings.group.reminders,
              children: <Widget>[
                _SettingsTile(
                  title: t.settings.reminders.notifications,
                  subtitle: t.settings.reminders.notificationsSubtitle,
                  onTap: () async {
                    try {
                      await AppSettings.openAppSettings(
                        type: AppSettingsType.notification,
                      );
                    } on Object {
                      // 防御：插件不可用时静默（测试环境/桌面端）。
                    }
                  },
                ),
              ],
            ),
            _SettingsGroup(
              title: t.settings.group.about,
              children: <Widget>[
                // 版本号与 pubspec version 对齐（1.0.0+1）。
                _SettingsTile(
                  title: t.settings.about.version,
                  trailing: '1.0.0 (1)',
                ),
                _SettingsTile(
                  title: t.settings.about.disclaimer,
                  onTap: () => context.push('/legal/disclaimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.auth.logoutConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t.auth.logout),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.auth.loggedOut)));
    }
  }

  /// 删除账号（§4.3）：确认弹窗明示后果 → 申请（进入 7 天冷静期〔假设〕）
  /// → 本地登出冻结。服务端 U5 未实现，当前走 stub 并标注。
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.account.deleteConfirmTitle),
        content: Text(t.settings.account.deleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: colors.signalRed),
            child: Text(t.settings.account.deleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(accountDeletionServiceProvider).requestDeletion();
    if (!context.mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.account.deleteRequested)),
      );
    }
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final path = await ref.read(dataExportServiceProvider).requestExport();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${t.settings.privacy.exportStubNote}\n'
            '${t.settings.privacy.exportSuccess(path: path)}',
          ),
        ),
      );
    }
  }

  Future<void> _setHealthData(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref
        .read(privacyConsentControllerProvider.notifier)
        .setHealthDataGranted(value);
    if (!value && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.of(context).settings.privacy.healthDataRevoked,
          ),
        ),
      );
    }
  }

  Future<void> _setAnalytics(WidgetRef ref, bool value) async {
    await ref.read(analyticsServiceProvider).setAnalyticsConsent(value);
    // ConsentStore 为同步读取，invalidate 触发开关状态刷新。
    ref.invalidate(analyticsEnabledProvider);
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.settings.language.title),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'system'),
            child: Text(t.settings.language.system),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'zh-CN'),
            child: Text(t.settings.language.zhCN),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'en'),
            child: Text(t.settings.language.en),
          ),
        ],
      ),
    );
    if (picked != null) {
      ref.read(languageModeProvider.notifier).setMode(picked);
    }
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.settings.theme.title),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ThemeMode.system),
            child: Text(t.settings.theme.system),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ThemeMode.light),
            child: Text(t.settings.theme.light),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ThemeMode.dark),
            child: Text(t.settings.theme.dark),
          ),
        ],
      ),
    );
    if (picked != null) {
      ref.read(themeModeProvider.notifier).setMode(picked);
    }
  }

  static String _languageLabel(Translations t, String mode) {
    return switch (mode) {
      LanguageModeController.zhCN => t.settings.language.zhCN,
      LanguageModeController.en => t.settings.language.en,
      _ => t.settings.language.system,
    };
  }

  static String _themeLabel(Translations t, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => t.settings.theme.light,
      ThemeMode.dark => t.settings.theme.dark,
      ThemeMode.system => t.settings.theme.system,
    };
  }
}

/// 分组卡片（设计稿卡片规范：bgSecondary + rLg 圆角 + 组标题）。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s1,
              bottom: AppSpacing.s2,
            ),
            child: Text(
              title,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: radii.rLg,
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 设置行（≥44px 触控区；trailing 文案或自定义控件如 Switch）。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.titleColor,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final Color? titleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: textStyles.textBase.copyWith(
                        color: titleColor ?? colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: textStyles.textXs.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailingWidget,
              if (trailing != null)
                Text(
                  trailing!,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              if (onTap != null && trailingWidget == null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

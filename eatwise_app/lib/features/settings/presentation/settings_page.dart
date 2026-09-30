import 'dart:async';
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/network/api_error_text.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/update/update_dialog.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_providers.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart'
    show localNotificationServiceProvider;
import 'package:eatwise/features/health/presentation/health_sync_section.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/record/application/water_reminder_planner.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/settings/application/avatar_upload.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:eatwise/features/social/presentation/pinned_post_image.dart';
import 'package:eatwise/features/streak/presentation/streak_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于区版本号（package_info_plus：`version (buildNumber)`，与
/// core/update/update_providers.dart 同源；测试注入固定值）。
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// 设置页（替换 我的 Tab 占位，M7 + 合规 D-18 落地）。
///
/// 分组卡片列表（设计稿卡片规范，行触控区 ≥44px）：
/// 账号（账号标识（username/脱敏手机号）/登出/删除账号冷静期 + 冷静期内
/// 状态与撤销）、隐私（协议/导出/健康数据授权/数据分析授权）、偏好
/// （语言/主题即时生效）、提醒（跳系统通知设置）、关于（版本/免责声明
/// 常驻入口，§5.1）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final userMe = ref.watch(userMeProvider).value;
    // 账号标识（D-13 v2）：username 主路径优先，其次脱敏手机号。
    final identity = userMe == null
        ? ''
        : (userMe.username.isNotEmpty ? userMe.username : userMe.maskedPhone);
    // 本地缓存兜底（U1 失败/离线时仍能看到账号标识）。
    final cachedIdentity =
        ref.watch(accountIdentityStoreProvider)?.read() ?? '';
    final healthGranted = ref.watch(
      privacyConsentControllerProvider.select((s) => s.healthDataGranted),
    );
    final analyticsGranted = ref.watch(analyticsEnabledProvider);
    // 登录态门控（走查：iOS 重装清 Keychain 后会话丢失，页面却仍显示
    // 登出/删除账号/修改密码——未登录点的全是死路）。口径与路由门禁同源
    // （AuthGate，restore/登录/登出翻转）；登出后 redirect 即离开本页。
    final loggedIn = ref.watch(authGateProvider).loggedIn;
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
            // 资料头卡（2026-09-30 吸收华为「我的」头卡语言：圆形头像占位
            // + 账号标识；无等级体系不引入不存在的数据，仅既有账号信息）。
            _ProfileHeaderCard(
              identity: identity,
              cachedIdentity: cachedIdentity,
              loggedIn: loggedIn,
              avatarUrl: userMe?.avatarUrl,
              onRetry: loggedIn && identity.isEmpty && cachedIdentity.isEmpty
                  ? () => ref.invalidate(userMeProvider)
                  : null,
            ),
            const SizedBox(height: AppSpacing.s4),
            // M5：连胜卡片保留（视觉随令牌简化）。
            const StreakProfileCard(),
            const SizedBox(height: AppSpacing.s6),
            // ① 身体与目标（2026-09-29 UI 重构：原 账号/隐私/偏好/提醒
            // 五组十几项归并 ≤4 组卡）。
            _SettingsGroup(
              title: t.settings.group.bodyGoals,
              children: <Widget>[
                // 阶段 A：身体档案（性别/出生年/身高体重/活动水平，
                // D-18 敏感信息可留空），保存即重算营养目标。
                _SettingsTile(
                  title: t.settings.bodyProfile.title,
                  subtitle: t.settings.bodyProfile.subtitle,
                  icon: Icons.monitor_weight_outlined,
                  onTap: () => context.push('/settings/body-profile'),
                ),
                // D-06 换方案入口：方案推荐页（已有生效方案且窗口不同时
                // 触发「次日 0:00 生效」确认弹窗）。
                _SettingsTile(
                  title: t.settings.fastingPlan.title,
                  subtitle: t.settings.fastingPlan.subtitle,
                  icon: Icons.schedule_outlined,
                  onTap: () => context.push('/settings/fasting-plan'),
                ),
                // 喝水提醒开关（默认开）：进食窗口内每小时提醒，建议量按
                // 当日剩余目标量动态分配；翻转即重排通知（异步无感）。
                _SettingsTile(
                  title: t.settings.reminders.waterHourly,
                  subtitle: t.settings.reminders.waterHourlySubtitle,
                  icon: Icons.water_drop_outlined,
                  trailingWidget: Switch(
                    value: ref.watch(waterReminderEnabledProvider),
                    onChanged: (value) async {
                      ref
                          .read(waterReminderEnabledProvider.notifier)
                          .setEnabled(value);
                      if (value) {
                        // 「用时申请」时机 = 用户主动开启提醒（合规 §3）；
                        // 拒绝不阻断开关状态，重排会走降级路径。
                        try {
                          await ref
                              .read(localNotificationServiceProvider)
                              .requestPermission();
                        } on Object {
                          // 防御：插件不可用（测试/桌面端）。
                        }
                      }
                      rescheduleWaterReminders(ref);
                    },
                  ),
                ),
                _SettingsTile(
                  title: t.settings.reminders.notifications,
                  subtitle: t.settings.reminders.notificationsSubtitle,
                  icon: Icons.notifications_outlined,
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
                _SettingsTile(
                  title: t.settings.privacy.healthData,
                  subtitle: t.settings.privacy.healthDataSubtitle,
                  icon: Icons.favorite_outline,
                  trailingWidget: Switch(
                    value: healthGranted,
                    onChanged: (value) => _setHealthData(context, ref, value),
                  ),
                ),
              ],
            ),
            // 阶段 D：运动数据（HealthKit / Health Connect，D-19 翻案）。
            const HealthSyncSection(),
            // ② 账号与安全。
            _SettingsGroup(
              title: t.settings.group.accountSecurity,
              children: <Widget>[
                // 冷静期内账号：状态行 + 撤销按钮（U6）。
                if (userMe?.deletionStatus == 'pending')
                  _SettingsTile(
                    title: t.settings.account.deletionScheduled(
                      days: _coolingOffDaysLeft(userMe!),
                    ),
                    icon: Icons.delete_forever_outlined,
                    iconColor: colors.signalRed,
                    titleColor: colors.signalRed,
                    trailingWidget: TextButton(
                      onPressed: () => _cancelDeletion(context, ref),
                      child: Text(t.settings.account.cancelDeletion),
                    ),
                  ),
                if (loggedIn) ...<Widget>[
                  _SettingsTile(
                    title: t.settings.account.changePassword,
                    icon: Icons.lock_outline,
                    onTap: () => context.push('/settings/change-password'),
                  ),
                ] else
                  _SettingsTile(
                    title: t.settings.account.login,
                    icon: Icons.login_outlined,
                    onTap: () => context.push('/login'),
                  ),
                _SettingsTile(
                  title: t.settings.account.contributions,
                  icon: Icons.restaurant_outlined,
                  onTap: () => context.push('/profile/contributions'),
                ),
                _SettingsTile(
                  title: t.settings.privacy.blockedUsers,
                  subtitle: t.settings.privacy.blockedUsersSubtitle,
                  icon: Icons.block_outlined,
                  onTap: () => context.push('/settings/blocked-users'),
                ),
                // 审批中心（用户角色 admin 可见；普通用户完全隐藏，
                // 服务端 UserAdminGuard 再兜底 403）。
                if (userMe?.role == 'admin')
                  _SettingsTile(
                    title: t.settings.account.moderation,
                    subtitle: t.moderation.subtitle,
                    icon: Icons.fact_check_outlined,
                    onTap: () => context.push('/moderation/food-candidates'),
                  ),
                if (loggedIn) ...<Widget>[
                  _SettingsTile(
                    title: t.settings.account.logout,
                    icon: Icons.logout_outlined,
                    onTap: () => _confirmLogout(context, ref),
                  ),
                  _SettingsTile(
                    title: t.settings.account.deleteAccount,
                    icon: Icons.delete_outline,
                    iconColor: colors.signalRed,
                    titleColor: colors.signalRed,
                    onTap: () => _confirmDeleteAccount(context, ref),
                  ),
                ],
              ],
            ),
            // ③ 数据与 AI。
            _SettingsGroup(
              title: t.settings.group.dataAi,
              children: <Widget>[
                // 用户自定义 LLM 配置（规格 §3）：/settings/ai-model。
                _SettingsTile(
                  title: t.settings.aiModel.title,
                  icon: Icons.psychology_outlined,
                  onTap: () => context.push('/settings/ai-model'),
                ),
                _SettingsTile(
                  title: t.settings.privacy.analytics,
                  subtitle: t.settings.privacy.analyticsSubtitle,
                  icon: Icons.analytics_outlined,
                  trailingWidget: Switch(
                    value: analyticsGranted,
                    onChanged: (value) => _setAnalytics(ref, value),
                  ),
                ),
                _SettingsTile(
                  title: t.settings.privacy.exportData,
                  icon: Icons.ios_share_outlined,
                  onTap: () => _exportData(context, ref),
                ),
                _SettingsTile(
                  title: t.settings.language.title,
                  icon: Icons.language_outlined,
                  trailing: _languageLabel(t, languageMode),
                  onTap: () => _pickLanguage(context, ref),
                ),
                _SettingsTile(
                  title: t.settings.theme.title,
                  icon: Icons.dark_mode_outlined,
                  trailing: _themeLabel(t, themeMode),
                  onTap: () => _pickTheme(context, ref),
                ),
              ],
            ),
            // ④ 关于与法务。
            _SettingsGroup(
              title: t.settings.group.aboutLegal,
              children: <Widget>[
                // 版本（安卓端点按=检查更新；iOS 更新完全依赖 App Store，
                // 不提供端内入口）。版本号读 package_info_plus
                // （version (buildNumber)），加载完成前占位不展示假版本。
                _SettingsTile(
                  title: t.settings.about.version,
                  icon: Icons.system_update_alt_outlined,
                  trailing:
                      ref.watch(appVersionLabelProvider).valueOrNull ?? '…',
                  onTap: ref.watch(updateCheckSupportedPlatformProvider)
                      ? () => _checkUpdate(context, ref)
                      : null,
                ),
                // 协议与说明合并入口（隐私政策/用户协议/免责声明/数据与
                // AI 说明四项收敛为一个入口，UI 重构「缩减与合并」）。
                _SettingsTile(
                  title: t.settings.about.legalHub,
                  icon: Icons.description_outlined,
                  onTap: () => unawaited(_showLegalHub(context)),
                ),
                // Flutter 官方开源许可页。
                _SettingsTile(
                  title: t.settings.about.licenses,
                  icon: Icons.code_outlined,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: Translations.of(context).common.appName,
                  ),
                ),
                _SettingsTile(
                  title: t.settings.about.contact,
                  icon: Icons.mail_outline,
                  trailing: 'chunguangwee@gmail.com',
                  onTap: () => unawaited(_contactSupport(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 「协议与说明」合并入口（UI 重构）：隐私政策/用户协议/免责声明/
  /// 数据与 AI 说明四项一个对话框承载。
  Future<void> _showLegalHub(BuildContext context) async {
    final t = Translations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.settings.about.legalHub),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/legal/privacy');
            },
            child: Text(t.settings.privacy.privacyPolicy),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/legal/agreement');
            },
            child: Text(t.settings.privacy.userAgreement),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/legal/disclaimer');
            },
            child: Text(t.settings.about.disclaimer),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_showDataAiNotes(context));
            },
            child: Text(t.settings.about.dataAi),
          ),
        ],
      ),
    );
  }

  /// 「数据与 AI 说明」对话框（营养数据来源 + Gemma 使用条款链接，法务上架补齐）。
  Future<void> _showDataAiNotes(BuildContext context) async {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.bgPrimary,
        title: Text(t.settings.about.dataAi, style: textStyles.textLg),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.settings.about.dataAiNutritionTitle,
              style: textStyles.textBase,
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              t.settings.about.dataAiNutritionBody,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(t.settings.about.dataAiModelTitle, style: textStyles.textBase),
            const SizedBox(height: AppSpacing.s1),
            Text(
              t.settings.about.dataAiModelBody,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s2),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.brandPrimary,
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse('https://ai.google.dev/gemma/terms'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              child: Text(
                t.settings.about.gemmaTerms,
                style: textStyles.textSm,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.common.action.cancel),
          ),
        ],
      ),
    );
  }

  /// 「联系我们」mailto 唤起（上架法务统一联系方式）。
  Future<void> _contactSupport(BuildContext context) async {
    await launchUrl(Uri.parse('mailto:chunguangwee@gmail.com'));
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
    // 账号标识缓存随登出清除（下次 U1 成功后重新写入）。
    await ref.read(accountIdentityStoreProvider)?.clear();
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.auth.loggedOut)));
    }
  }

  /// 删除账号（§4.3）：确认弹窗明示后果 → U5 申请（进入冷静期，服务端
  /// 吊销全部会话）→ 冷静期弹窗（显示截止日期）→ 本地登出冻结。
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
    final AccountDeletionView view;
    try {
      view = await ref.read(accountDeletionServiceProvider).requestDeletion();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorDisplayMessage(t, e))));
      }
      return;
    }
    if (!context.mounted) return;
    // 冷静期确认弹窗：显示截止日期（本地时区日期）。
    final deadline = view.scheduledDeletionAt?.toLocal();
    final dateText = deadline == null
        ? ''
        : '${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-'
              '${deadline.day.toString().padLeft(2, '0')}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.account.deleteConfirmTitle),
        content: Text(t.settings.account.deleteScheduledBody(date: dateText)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.common.action.confirm),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    // 删除申请已受理：账号标识缓存一并清除。
    await ref.read(accountIdentityStoreProvider)?.clear();
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.account.deleteRequested)),
      );
    }
  }

  /// 冷静期内撤销删除（U6）：成功后刷新账号状态并提示。
  Future<void> _cancelDeletion(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    try {
      await ref.read(accountDeletionServiceProvider).cancelDeletion();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorDisplayMessage(t, e))));
      }
      return;
    }
    ref.invalidate(userMeProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.account.deletionCancelled)),
      );
    }
  }

  /// 冷静期剩余天数（向上取整，状态行展示用）。
  static int _coolingOffDaysLeft(UserMeView userMe) {
    final deadline = userMe.scheduledDeletionAt;
    if (deadline == null) return 0;
    final left = deadline.difference(DateTime.now()).inHours;
    return left <= 0 ? 0 : (left / 24).ceil();
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    try {
      final path = await ref.read(dataExportServiceProvider).requestExport();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.settings.privacy.exportSuccess(path: path))),
        );
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // 业务错误用服务端本地化文案；网络/超时走本地双语兜底。
      final message = e is BusinessApiException
          ? e.message
          : t.settings.privacy.exportFailed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 「检查更新」（手动触发，不节流）：有更新弹窗；已是最新 SnackBar 提示。
  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final UpdateCheckResult result;
    try {
      result = await ref.read(updateCoordinatorProvider).checkManually();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.update.checkFailed)));
      }
      return;
    }
    if (!context.mounted) return;
    if (result.status == UpdateStatus.upToDate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.update.upToDate)));
      return;
    }
    await showUpdateDialog(
      context,
      result,
      launcher: ref.read(updateLauncherProvider),
      downloader: ref.read(updateDownloaderProvider),
    );
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

/// 资料头卡（2026-09-30，吸收华为运动健康「我的」头卡语言）：
/// 圆形头像（已设置显示照片，未设置显品牌绿浅底占位）+ 账号标识
///（D-13 v2：username 主路径优先，其次 U1 脱敏手机号；兜底链：实时值 →
/// 本地缓存 → 未登录占位）+ 「账号」小标签。已登录但标识取不到（重装清
/// 缓存 + U1 失败）时显「点击重试」并可点重拉（与登录态不矛盾；我们
/// 没有等级/成长体系，不引入不存在的数据）。
///
/// 头像更换（同日新增）：登录态点头像 → 拍照/相册来源弹层 →
/// 上传回写 PATCH /users/me（`uploadAvatar` 全链路）；右下角相机角标
/// 提示可点，上传在途禁用入口并显进度。
class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard({
    required this.identity,
    required this.cachedIdentity,
    required this.loggedIn,
    this.avatarUrl,
    this.onRetry,
  });

  final String identity;
  final String cachedIdentity;
  final bool loggedIn;

  /// 头像 URL（相对路径 /v1/uploads/xxx 或 http(s)；null 显占位图标）。
  final String? avatarUrl;

  /// 标识取不到时的重试动作（null = 不可点）。
  final VoidCallback? onRetry;

  /// 来源选择弹层（拍照 / 相册；小内容弹层，与拍照识别入口同语言）。
  Future<void> _showSourceSheet(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      backgroundColor: colors.bgSecondary,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: colors.brandPrimary,
              ),
              title: Text(t.settings.account.avatar.takePhoto),
              onTap: () => Navigator.pop(sheetContext, PhotoSource.camera),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: colors.brandPrimary,
              ),
              title: Text(t.settings.account.avatar.fromGallery),
              onTap: () => Navigator.pop(sheetContext, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    final result = await uploadAvatar(ref, source);
    if (!context.mounted) return;
    switch (result) {
      case AvatarUploadResult.success:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.settings.account.avatar.success)),
        );
      case AvatarUploadResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.settings.account.avatar.failed)),
        );
      case AvatarUploadResult.permissionDenied:
        _showPermissionDeniedDialog(context, t, textStyles);
      case AvatarUploadResult.cancelled:
        break;
    }
  }

  /// 权限被拒降级（§4.3）：说明 + 直达系统设置。
  void _showPermissionDeniedDialog(
    BuildContext context,
    Translations t,
    AppTextStyles textStyles,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.account.avatar.deniedTitle),
        content: Text(
          t.settings.account.avatar.deniedBody,
          style: textStyles.textSm,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await AppSettings.openAppSettings();
              } on Object {
                // 防御：插件不可用时静默（测试环境/桌面端）。
              }
            },
            child: Text(t.settings.account.avatar.openSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final uploading = ref.watch(avatarUploadingProvider);
    final display = identity.isNotEmpty
        ? identity
        : cachedIdentity.isNotEmpty
        ? cachedIdentity
        : loggedIn
        ? t.settings.account.retryIdentity
        : t.settings.account.notLoggedIn;
    // 服务端回相对路径（/v1/uploads/<id>），渲染前补 origin；加载走
    // 带证书锁定的 dio（PinnedPostImage），生产自签证书下裸 Image.network
    // 握手必败断图。
    final resolvedAvatarUrl = avatarUrl != null && avatarUrl!.isNotEmpty
        ? ref.watch(apiConfigProvider).resolveUrl(avatarUrl!)
        : null;
    return Material(
      color: colors.bgSecondary,
      borderRadius: radii.rLg,
      child: InkWell(
        onTap: onRetry,
        borderRadius: radii.rLg,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: radii.rLg,
            boxShadow: shadows.shadowSm,
          ),
          child: Row(
            children: <Widget>[
              // 头像（可点更换）：照片 / 品牌绿浅底占位 + 相机角标。
              GestureDetector(
                key: const ValueKey<String>('settings.avatar.edit'),
                onTap: loggedIn && !uploading
                    ? () => _showSourceSheet(context, ref)
                    : null,
                child: Stack(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.brandPrimary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: uploading
                          ? Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.brandPrimary,
                                ),
                              ),
                            )
                          : resolvedAvatarUrl != null
                          ? _AvatarImage(
                              key: ValueKey<String>(resolvedAvatarUrl),
                              url: resolvedAvatarUrl,
                            )
                          : Icon(
                              Icons.person_outline,
                              size: 26,
                              color: colors.brandPrimary,
                            ),
                    ),
                    if (loggedIn && !uploading)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colors.brandPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.bgSecondary,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      display,
                      style: textStyles.textLg.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      uploading
                          ? t.settings.account.avatar.uploading
                          : t.settings.account.account,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRetry != null)
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

/// 分组卡片（设计稿卡片规范：bgSecondary + rLg 圆角 + 组标题；
/// 2026-09-29 UI 重构加 shadowSm 软阴影，对齐华为白卡语言）。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
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
              boxShadow: shadows.shadowSm,
            ),
            clipBehavior: Clip.antiAlias,
            // 组内行间细分隔线（hairline，缩进对齐图标右侧文字起点
            // 56px = 行左右边距 16 + 图标徽标 32 + 图标-文字间距 8，
            // 参考华为运动健康「我的」分隔线留白）。
            child: Column(
              children: <Widget>[
                for (var i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 56,
                      color: colors.textSecondary.withValues(alpha: 0.12),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置行（≥56px 触控区，对齐华为「我的」行高节奏；前置品牌绿浅底
/// 圆形图标徽标（与 MetricCard 徽标同语言，全页统一），trailing 文案或
/// 自定义控件如 Switch）。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.titleColor,
    this.iconColor,
    this.onTap,
  });

  final String title;

  /// 前置线性图标（Icons.outlined 系，18px）。
  final IconData icon;

  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final Color? titleColor;

  /// 图标与徽标底色（默认品牌绿；危险动作用 signalRed）。
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final tint = iconColor ?? colors.brandPrimary;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: <Widget>[
              // 品牌绿浅底圆形徽标（32px，与首页 MetricCard 同语言）。
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: AppSpacing.s2),
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
                // 长值（如脱敏手机号）限宽省略，不再把标题挤成竖排；
                // 短值保持原样贴右（标题 Expanded 吸收剩余空间）。
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
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

/// 头像小图：经带证书锁定的加载器拉字节（生产自签证书下裸
/// Image.network 握手必败）；加载中/失败统一回退人形占位——
/// 头像位显断图图标比显占位更刺眼（与 feed 大图的断图占位口径不同）。
class _AvatarImage extends ConsumerStatefulWidget {
  const _AvatarImage({required this.url, super.key});

  final String url;

  @override
  ConsumerState<_AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends ConsumerState<_AvatarImage> {
  Future<Uint8List?>? _future;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    _future ??= ref.read(pinnedPostImageLoaderProvider).load(widget.url);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Icon(
            Icons.person_outline,
            size: 26,
            color: colors.brandPrimary,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          gaplessPlayback: true,
        );
      },
    );
  }
}

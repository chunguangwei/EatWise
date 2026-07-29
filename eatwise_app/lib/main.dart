import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/app/router/app_router.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/notification/local_notification_service.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_seed_loader.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // D-15：默认跟随系统语言；设置内手动切换见 Demo 页示例。
  await LocaleSettings.useDeviceLocale();
  // 时区数据库（D-07：UTC 存储本地渲染，M2 引擎锚点换算依赖）。
  // 加载失败不阻断启动，由 deviceLocationProvider 回退 UTC 防御。
  try {
    final data = await rootBundle.load('packages/timezone/data/latest_all.tzf');
    tz.initializeDatabase(data.buffer.asUint8List());
  } on Object {
    // 防御：时区数据缺失时按 UTC 渲染，引导主流程不阻断。
  }
  // M1：读取引导完成标志位，决定首屏进入 /onboarding 还是首页。
  final prefs = await SharedPreferences.getInstance();
  final gate = OnboardingGate(
    completed: SharedPreferencesOnboardingStore(prefs).isOnboardingCompleted,
  );
  // M3/M7：本地数据库（drift，D-17；SQLCipher 加密接入点见规格-数据同步 §7.2）。
  final docsDir = await getApplicationDocumentsDirectory();
  final db = AppDatabase.openAt(docsDir.path);
  // D-16：首次启动导入双语食物库种子（幂等，按版本号跳过）；
  // 资产缺失/解析失败不阻断启动，食物搜索降级为仅已导入数据。
  try {
    await FoodSeedLoader(db: db, prefs: prefs).ensureSeeded();
  } on Object {
    // 防御：种子导入失败时手动录入与已入库数据仍可用。
  }
  // M2：本地通知服务初始化（D-09；失败不阻断计时主流程，权限拒绝走
  // App 内横幅降级，合规 §3）。渠道文案走 i18n（D-15）。
  final notificationService = LocalNotificationService();
  try {
    await notificationService.initialize(
      channel: fastingReminderChannel(LocaleSettings.currentLocale.buildSync()),
    );
  } on Object {
    // 防御：通知插件初始化失败时计时照常，提醒功能降级。
  }
  // D-13：登录门禁（独立标志，与引导门禁协调）；令牌存 Keychain/Keystore
  // （契约 §6.2）。启动恢复会话：有 refreshToken 即登录态，accessToken
  // 过期由拦截器 401 refresh 无感续期。
  final authGate = AuthGate();
  // session 清理回调需引用 container 自身：先留位后赋值，回避自引用。
  void Function()? handleSessionCleared;
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      onboardingGateProvider.overrideWithValue(gate),
      appDatabaseProvider.overrideWithValue(db),
      localNotificationServiceProvider.overrideWithValue(notificationService),
      tokenStoreProvider.overrideWithValue(SecureTokenStore()),
      authGateProvider.overrideWithValue(authGate),
      // refresh 失败清会话 → 强制回登录页。
      apiSessionClearedHandlerProvider.overrideWithValue(
        () => handleSessionCleared?.call(),
      ),
      // 首页信号卡数据源：record 仓储当日聚合流（本地预估，§2.6）。
      todayNutritionCacheProvider.overrideWith(
        (ref) => ref
            .watch(recordRepositoryProvider)
            .watchDailyNutrition(DateTime.now()),
      ),
    ],
  );
  handleSessionCleared = () =>
      container.read(authControllerProvider.notifier).onSessionCleared();
  await container.read(authControllerProvider.notifier).restore();
  // 埋点采集层（D-01 北极星口径 / D-18：默认未授权不采集，授权入口见
  // ConsentStore，隐私弹窗 UI 留 TODO）：定时 flush + 启动重放离线队列 +
  // 前后台会话切分；未授权时下列事件均为 suppressed no-op。
  final analytics = container.read(analyticsServiceProvider)..start();
  WidgetsBinding.instance.addObserver(analytics);
  analytics.trackAppOpen(launchType: 'cold');
  if (authGate.loggedIn) {
    // §2.1：App 启动触发一轮同步（先上行 pending 再增量下行）。
    unawaited(container.read(recordSyncEngineProvider).syncNow());
  }
  runApp(
    TranslationProvider(
      child: UncontrolledProviderScope(
        container: container,
        child: EatWiseApp(gate: gate, authGate: authGate),
      ),
    ),
  );
}

class EatWiseApp extends StatefulWidget {
  const EatWiseApp({super.key, this.gate, this.authGate});

  /// 新手引导门禁；缺省按「已完成」处理（保留 M0 演示冒烟路径）。
  final OnboardingGate? gate;

  /// 登录门禁（D-13）；缺省视为已登录（保留既有测试/演示路径）。
  final AuthGate? authGate;

  @override
  State<EatWiseApp> createState() => _EatWiseAppState();
}

class _EatWiseAppState extends State<EatWiseApp> {
  late final GoRouter _router = createAppRouter(
    gate: widget.gate ?? OnboardingGate(completed: true),
    authGate: widget.authGate,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      routerConfig: _router,
      // 主题：亮/暗/跟随系统（设计稿 §2.1，Token 见 core/theme）。
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // i18n（slang，D-15）。
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

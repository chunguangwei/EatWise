import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/app/router/app_router.dart';
import 'package:eatwise/core/notification/local_notification_service.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_seed_loader.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
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
  runApp(
    TranslationProvider(
      child: ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          onboardingGateProvider.overrideWithValue(gate),
          appDatabaseProvider.overrideWithValue(db),
          localNotificationServiceProvider.overrideWithValue(
            notificationService,
          ),
          // 首页信号卡数据源：record 仓储当日聚合流（本地预估，§2.6）。
          todayNutritionCacheProvider.overrideWith(
            (ref) => ref
                .watch(recordRepositoryProvider)
                .watchDailyNutrition(DateTime.now()),
          ),
        ],
        child: EatWiseApp(gate: gate),
      ),
    ),
  );
}

class EatWiseApp extends StatefulWidget {
  const EatWiseApp({super.key, this.gate});

  /// 新手引导门禁；缺省按「已完成」处理（保留 M0 演示冒烟路径）。
  final OnboardingGate? gate;

  @override
  State<EatWiseApp> createState() => _EatWiseAppState();
}

class _EatWiseAppState extends State<EatWiseApp> {
  late final GoRouter _router = createAppRouter(
    gate: widget.gate ?? OnboardingGate(completed: true),
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

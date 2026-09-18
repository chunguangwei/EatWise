import 'package:dio/dio.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart' show EntrySource;
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../record/record_test_helper.dart';

/// B1 冷启动营养数据假空态回归（v1.2.1 走查）：
/// 重启 App 后登录态从 Keychain 恢复，但 userId 此前只存在于内存
/// （仅登录时 _applySession 写入），restore() 只翻转 status 不恢复
/// userId → currentUserIdProvider 恒 anonymous → 数据页/首页信号卡/
/// 记录页/趋势/月报全部按 anonymous 查询落空（旧数据在真实 userId 下）。
/// 修复：userId 随令牌持久化（TokenStore），restore() 一并恢复。
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late InMemoryTokenStore tokenStore;
  late AuthGate authGate;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    tokenStore = InMemoryTokenStore();
    authGate = AuthGate();
  });

  tearDown(() async {
    await db.close();
  });

  /// 冷启动装配：真实 currentUserIdProvider 链路（authController → restore），
  /// 不 override userId；dio 仅占位（restore 不发网络请求）。
  ///
  /// 时钟口径：测试环境 tz.local 为 UTC（未 setLocalLocation），写入侧
  /// （RecordRepository 归属日）按 UTC 换算；读取侧「今天」默认取设备本地
  /// DateTime.now()，在本地日 ≠ UTC 日的时间窗（如 UTC+8 的 00:00–08:00）
  /// 两侧日期错位、查询落空。故数据页/报告页时钟钉到 UTC 基准与写入侧
  /// 对齐（生产 main() 会 tz.setLocalLocation(设备时区)，天然同口径）。
  ProviderContainer makeColdStartContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        recordRemoteProvider.overrideWithValue(FakeRecordRemote()),
        tokenStoreProvider.overrideWithValue(tokenStore),
        authGateProvider.overrideWithValue(authGate),
        nutritionNowProvider.overrideWithValue(DateTime.now().toUtc()),
        reportsNowProvider.overrideWithValue(DateTime.now().toUtc()),
        authControllerProvider.overrideWith((ref) {
          return AuthController(
            api: AuthApi(Dio()),
            tokenStore: tokenStore,
            gate: authGate,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 模拟「上一次登录会话」：以 u-A 口径写入今日饮食 + 饮水，并把
  /// 登录会话（含 userId）持久化到令牌存储（登录时 _applySession 的行为）。
  Future<void> seedPreviousSessionAsUserA() async {
    final session = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        recordRemoteProvider.overrideWithValue(FakeRecordRemote()),
        currentUserIdProvider.overrideWithValue('u-A'),
      ],
    );
    await session
        .read(recordRepositoryProvider)
        .addEntry(
          RecordDraft(
            foodId: 'f-rice',
            amountG: 100,
            mealUtc: DateTime.now().toUtc(),
            source: EntrySource.manual,
          ),
        );
    await session.read(waterLogRepositoryProvider).add(300);
    session.dispose();
    await tokenStore.saveTokens(
      accessToken: 'at-A',
      refreshToken: 'rt-A',
      userId: 'u-A',
    );
  }

  test('冷启动 anonymous→u-A 时序：restore 后各读取链重查并读到 u-A 数据', () async {
    await seedPreviousSessionAsUserA();
    final container = makeColdStartContainer();

    // restore 前（假空态复现）：登录态未恢复，按 anonymous 查询落空。
    expect(container.read(currentUserIdProvider), 'anonymous');
    expect(await container.read(dayCacheProvider.future), isNull);
    expect(container.read(dayIntakeProvider), isNull);

    // 登录态恢复（main() 启动路径：restore 先于 runApp await 完成）。
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(currentUserIdProvider), 'u-A');

    // 数据页：当日聚合 + 近 7 日趋势重查命中 u-A。
    final cache = await container.read(dayCacheProvider.future);
    expect(cache, isNotNull);
    expect(cache!.userId, 'u-A');
    expect(cache.entryCount, 1);
    expect(cache.kcal, 116); // 白米饭 116 kcal/100g × 100g
    expect(container.read(dayIntakeProvider), isNotNull);
    await container.read(weeklyTrendProvider.future);
    expect(container.read(weeklyKcalProvider).last, 116);

    // 首页信号卡/记录页今日汇总（record 仓储当日聚合流）。
    final today = await container.read(recordTodayNutritionProvider.future);
    expect(today, isNotNull);
    expect(today!.entryCount, 1);

    // 记录页饮水轻量区。
    expect(await container.read(todayWaterTotalProvider.future), 300);

    // 趋势/月报（reports 窗口默认 7 天，终点今天）。
    final report = await container.read(reportNutritionProvider.future);
    expect(report.any((c) => c.userId == 'u-A' && c.entryCount == 1), isTrue);
  });

  test('旧版本会话（令牌存储无 userId）→ restore 后维持 anonymous 兜底', () async {
    await tokenStore.saveTokens(accessToken: 'at', refreshToken: 'rt');
    final container = makeColdStartContainer();

    await container.read(authControllerProvider.notifier).restore();

    // 老用户升级后首次启动尚无持久化 userId：口径与修复前一致
    // （anonymous），下次登录即写入并自愈。
    expect(container.read(authControllerProvider).status, AuthStatus.loggedIn);
    expect(container.read(currentUserIdProvider), 'anonymous');
  });
}

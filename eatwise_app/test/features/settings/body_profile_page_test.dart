import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/settings/presentation/body_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

/// 「我的-身体档案」页（阶段 A）：本地落盘 + 营养目标重算 +
/// 登录态 PATCH /users/me（U2）/ 未登录纯本地 / 服务端档案预填。
void main() {
  // 固定时钟：2026-07-28 UTC → currentYear=2026。
  final fixedNowUtc =
      DateTime.utc(2026, 7, 28, 7).millisecondsSinceEpoch ~/ 1000;

  late SharedPreferences prefs;
  late OnboardingStore store;
  late FakeHttpAdapter adapter;
  late InMemoryTokenStore tokenStore;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    store = SharedPreferencesOnboardingStore(prefs);
    adapter = FakeHttpAdapter(
      // 默认 U1：空档案用户（预填用例单独 stub 覆盖顺序消费）。
      fallback: StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{'id': 'u1', 'phone': '+8613****8000'},
          'nutritionTargets': <String, dynamic>{
            'kcal': 2000,
            'proteinG': 125,
            'carbsG': 225,
            'fatG': 67,
            'fallback': true,
          },
        }),
      ),
    );
    tokenStore = InMemoryTokenStore();
  });

  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
  });

  /// 装配页面；[loggedIn] 为 true 时预置会话令牌并以登录态启动。
  Future<void> pumpPage(WidgetTester tester, {required bool loggedIn}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    AuthController? authController;
    if (loggedIn) {
      await tokenStore.saveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'u1',
      );
      authController = AuthController(
        api: AuthApi(createApiDio(config: ApiConfig(), tokenStore: tokenStore)),
        tokenStore: tokenStore,
        gate: AuthGate(),
      );
      await authController.restore();
    }

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            tokenStoreProvider.overrideWithValue(tokenStore),
            nowUtcProvider.overrideWithValue(fixedNowUtc),
            apiDioProvider.overrideWith((ref) {
              final dio = createApiDio(
                config: ApiConfig(),
                tokenStore: tokenStore,
              );
              dio.httpClientAdapter = adapter;
              dio.interceptors
                      .whereType<AuthInterceptor>()
                      .single
                      .refreshDio
                      .httpClientAdapter =
                  adapter;
              return dio;
            }),
            if (authController != null)
              authControllerProvider.overrideWith((ref) => authController!),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const BodyProfilePage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapVisible(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// 已发出的 PATCH /users/me 请求数（U1 GET 同路径，需按方法区分）。
  int patchCount() => adapter.requests
      .where((r) => r.path == '/users/me' && r.method == 'PATCH')
      .length;

  testWidgets('未登录：保存只落本地（档案 + 营养目标重算），不发 PATCH', (tester) async {
    await pumpPage(tester, loggedIn: false);
    expect(find.text('身体档案'), findsOneWidget);

    // 男 / 1990（2026 年 36 岁）/ 176cm / 75kg / 轻度 →
    // BMR 1675 × 1.375 = 2303.125 → 取整 2300（maintain ×1.0）。
    await tester.tap(find.text('男'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1990',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '176',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '75',
    );
    await tester.pump();
    await tapVisible(tester, const ValueKey<String>('profile.activity.light'));
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );

    final profile = store.loadProfile()!;
    expect(profile.sex, ProfileSex.male);
    expect(profile.birthYear, 1990);
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isFalse);
    expect(goal.targetKcal, 2300);
    expect(find.textContaining('2300 kcal'), findsOneWidget);
    // 未登录：无 PATCH（U1 GET 预填不算）。
    expect(patchCount(), 0);
  });

  testWidgets('已登录：保存后 PATCH /users/me 上送档案字段', (tester) async {
    await pumpPage(tester, loggedIn: true);

    await tester.tap(find.text('女'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1998',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '162',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '55',
    );
    await tester.pump();
    await tapVisible(
      tester,
      const ValueKey<String>('profile.activity.sedentary'),
    );
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );
    // PATCH 成功后 invalidate userMeProvider 触发二次 GET，多补几帧冲刷
    // Dio 零时长 Timer，避免用例末尾 pending timer 告警。
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(patchCount(), 1);
    // requestBodies 与 requests 同序：按方法挑出 PATCH 的 body（末位是二次 GET）。
    final patchIndex = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    final patch = adapter.requestBodies[patchIndex] as Map<String, dynamic>;
    expect(patch['gender'], 'female');
    expect(patch['birthYear'], 1998);
    expect(patch['heightCm'], 162);
    expect(patch['weightKg'], 55);
    expect(patch['activityLevel'], 'sedentary');

    // 服务端档案未设 goal → 维持：TDEE = 1261.5 × 1.2 = 1513.8 → 1510。
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isFalse);
    expect(goal.targetKcal, 1510);
  });

  testWidgets('本地无档案且已登录：表单用服务端档案预填', (tester) async {
    // 覆盖默认 U1：带档案用户（fallback 是兜底，stub 优先消费）。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u1',
            'phone': '+8613****8000',
            'gender': 'male',
            'birthYear': 1990,
            'heightCm': 176.0,
            'weightKg': 75.0,
            'activityLevel': 'light',
          },
          'nutritionTargets': <String, dynamic>{
            'kcal': 2390,
            'proteinG': 149,
            'carbsG': 269,
            'fatG': 80,
            'fallback': false,
          },
        }),
      ),
    );
    await pumpPage(tester, loggedIn: true);

    TextField fieldOf(Key key) => tester.widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    );
    expect(
      fieldOf(const ValueKey<String>('profile.birthYear')).controller!.text,
      '1990',
    );
    expect(
      fieldOf(const ValueKey<String>('profile.heightCm')).controller!.text,
      '176',
    );
    expect(
      fieldOf(const ValueKey<String>('profile.weightKg')).controller!.text,
      '75',
    );
  });

  testWidgets('阶段 B：编辑目标体重/目标日期 → 保存 PATCH 上送并按缺口法重算', (tester) async {
    // 服务端档案带 fat_loss 目标（缺口法前提）。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u1',
            'phone': '+8613****8000',
            'goal': 'fat_loss',
          },
          'nutritionTargets': <String, dynamic>{
            'kcal': 1200,
            'proteinG': 75,
            'carbsG': 135,
            'fatG': 40,
            'fallback': false,
          },
        }),
      ),
    );
    await pumpPage(tester, loggedIn: true);

    await tester.tap(find.text('女'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1998',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '162',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '70',
    );
    await tester.pump();
    await tapVisible(
      tester,
      const ValueKey<String>('profile.activity.sedentary'),
    );

    // 目标：50 kg / 8 周（2026-09-22）→ 原始 2.5 kg/周 → 夹取 1.0。
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '50',
    );
    await tester.pump();
    await tapVisible(tester, const ValueKey<String>('goal.quickWeeks.8'));
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(patchCount(), 1);
    final patchIndex = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    final patch = adapter.requestBodies[patchIndex] as Map<String, dynamic>;
    expect(patch['targetWeightKg'], 50);
    expect(patch['targetDate'], '2026-09-22');

    // 当日重算：TDEE 1693.8 − 1100 → 下限 1200；快照带缺口法字段。
    final goal = store.loadNutritionGoal()!;
    expect(goal.targetKcal, 1200);
    expect(goal.weeklyRateKg, 1.0);
    expect(goal.weightLossClamped, isTrue);
    expect(goal.reachDate, '2026-12-15'); // 20kg ÷ 1kg/周 = 140 天
    final profile = store.loadProfile()!;
    expect(profile.targetWeightKg, 50);
    expect(profile.targetDate?.toIsoString(), '2026-09-22');
  });

  testWidgets('阶段 B：目标可清空 → PATCH 显式传 null，回落固定折算', (tester) async {
    // 服务端档案已有目标（预填）+ fat_loss。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u1',
            'phone': '+8613****8000',
            'gender': 'female',
            'birthYear': 1998,
            'heightCm': 162.0,
            'weightKg': 70.0,
            'activityLevel': 'sedentary',
            'goal': 'fat_loss',
            'targetWeightKg': 50.0,
            'targetDate': '2026-09-22',
          },
          'nutritionTargets': <String, dynamic>{
            'kcal': 1200,
            'proteinG': 75,
            'carbsG': 135,
            'fatG': 40,
            'fallback': false,
          },
        }),
      ),
    );
    await pumpPage(tester, loggedIn: true);

    // 目标字段已预填。
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('goal.targetWeight')),
          )
          .controller!
          .text,
      '50',
    );
    // 日期预览在 ListView 懒构建区域，先滚动到可见。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('goal.datePreview')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    // 本测试的 MaterialApp 未装 zh 代理，预览可能为 ISO 或中文格式。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('goal.datePreview')))
          .data,
      anyOf('2026年9月22日', '2026-09-22'),
    );

    // 清空目标体重 + 清除日期。
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '',
    );
    await tester.pump();
    await tapVisible(tester, const ValueKey<String>('goal.clearDate'));
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final patchIndex = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    final patch = adapter.requestBodies[patchIndex] as Map<String, dynamic>;
    expect(patch.containsKey('targetWeightKg'), isTrue);
    expect(patch['targetWeightKg'], isNull);
    expect(patch['targetDate'], isNull);

    // 回落 D-04 固定折算：1693.8 × 0.8 = 1355.04 → 1360；无缺口法字段。
    final goal = store.loadNutritionGoal()!;
    expect(goal.targetKcal, 1360);
    expect(goal.weeklyRateKg, isNull);
    expect(store.loadProfile()!.hasWeightGoal, isFalse);
  });

  testWidgets('BMI 卡：缺身高体重走补全引导，填齐后实时显示数值+徽标', (tester) async {
    await pumpPage(tester, loggedIn: false);

    // 空档案 → 引导文案，无 BMI 数值。
    expect(find.text('补全身高体重后展示 BMI'), findsOneWidget);
    expect(find.text('标准'), findsNothing);

    // 只填身高 → 仍是引导。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '176',
    );
    await tester.pump();
    expect(find.text('补全身高体重后展示 BMI'), findsOneWidget);

    // 填齐 → BMI 24.2（75 / 1.76²），偏高徽标。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '75',
    );
    await tester.pump();
    expect(find.text('补全身高体重后展示 BMI'), findsNothing);
    expect(find.text('24.2'), findsOneWidget);
    expect(find.text('偏高'), findsOneWidget);

    // 改体重 → 实时联动到标准区间（60 / 1.76² ≈ 19.4）。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '60',
    );
    await tester.pump();
    expect(find.text('19.4'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('偏高'), findsNothing);
  });

  testWidgets('设置页表单：切斤后预填换算为斤数，保存按 kg 上送并持久化偏好', (tester) async {
    // 服务端档案 75kg（预填）。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u1',
            'phone': '+8613****8000',
            'gender': 'male',
            'birthYear': 1990,
            'heightCm': 176.0,
            'weightKg': 75.0,
            'activityLevel': 'light',
          },
          'nutritionTargets': <String, dynamic>{
            'kcal': 2390,
            'proteinG': 149,
            'carbsG': 269,
            'fatG': 80,
            'fallback': false,
          },
        }),
      ),
    );
    await pumpPage(tester, loggedIn: true);

    TextField weightField() => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile.weightKg')),
        matching: find.byType(TextField),
      ),
    );
    // kg 预填；切斤 → 显示换算后的斤数（75kg → 150 斤）。
    // 页面上体重/目标两处单位切换，按 key 限定档案区。
    expect(weightField().controller!.text, '75');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile.weightUnit')),
        matching: find.text('斤'),
      ),
    );
    await tester.pump();
    expect(weightField().controller!.text, '150');
    expect(find.text('体重（斤）'), findsOneWidget);

    // 按斤填 170 → 保存上送 85 kg。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '170',
    );
    await tester.pump();
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final patchIndex = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    final patch = adapter.requestBodies[patchIndex] as Map<String, dynamic>;
    expect(patch['weightKg'], 85);
    // 本地档案同样按 kg 落盘。
    expect(store.loadProfile()!.weightKg, 85);
    // 单位偏好持久化（三处输入共用同一键）。
    expect(prefs.getString('profile.weightUnit'), 'jin');
  });

  testWidgets('目标体重：斤模式填 100 斤 → PATCH targetWeightKg=50（按 kg 存储），'
      '与档案区共用单位偏好实时联动', (tester) async {
    // 服务端档案带 fat_loss 目标（缺口法前提）+ 75kg 预填。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u1',
            'phone': '+8613****8000',
            'gender': 'male',
            'birthYear': 1990,
            'heightCm': 176.0,
            'weightKg': 75.0,
            'activityLevel': 'light',
            'goal': 'fat_loss',
          },
          'nutritionTargets': <String, dynamic>{
            'kcal': 1900,
            'proteinG': 119,
            'carbsG': 214,
            'fatG': 63,
            'fallback': false,
          },
        }),
      ),
    );
    await pumpPage(tester, loggedIn: true);

    TextField fieldOf(Key key) => tester.widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    );

    // 目标区默认公斤：先填 60，切斤后换算显示 120（旧单位换算重填）。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('goal.weightUnit')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '60',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('goal.weightUnit')),
        matching: find.text('斤'),
      ),
    );
    await tester.pump();
    expect(find.text('目标体重（斤）'), findsOneWidget);
    expect(
      // WeightGoalFields 的 key 直接挂在 TextField 上（非包裹容器）。
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('goal.targetWeight')),
          )
          .controller!
          .text,
      '120',
    );
    // 偏好共用实时联动：档案区体重字段同步切斤（预填 75kg → 150 斤）。
    // ListView 懒构建：档案区在上方，先滚回可见再取值。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      fieldOf(const ValueKey<String>('profile.weightKg')).controller!.text,
      '150',
    );

    // 非法：700 斤 = 350 kg 越域（按 kg 口径校验）→ 错误文案 + 保存禁用。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '700',
    );
    await tester.pump();
    expect(find.text('请输入 50–600 之间的体重（斤）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings.bodyProfile.save')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings.bodyProfile.save')),
          )
          .onPressed,
      isNull,
    );

    // 100 斤 → 合法；快捷 8 周（2026-09-22）→ 保存。
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '100',
    );
    await tester.pump();
    expect(find.text('请输入 50–600 之间的体重（斤）'), findsNothing);
    await tapVisible(tester, const ValueKey<String>('goal.quickWeeks.8'));
    await tapVisible(
      tester,
      const ValueKey<String>('settings.bodyProfile.save'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // PATCH 与本地档案均按 kg 存储（100 斤 → 50 kg）；档案区体重 150 斤 → 75kg。
    final patchIndex = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    final patch = adapter.requestBodies[patchIndex] as Map<String, dynamic>;
    expect(patch['targetWeightKg'], 50);
    expect(patch['weightKg'], 75);
    expect(store.loadProfile()!.targetWeightKg, 50);
    expect(prefs.getString('profile.weightUnit'), 'jin');
  });

  testWidgets('BMI > 35：卡内追加「体重单位是公斤」提示行，回落后消失', (tester) async {
    await pumpPage(tester, loggedIn: false);
    const hint = '体重单位是公斤，如果你是按斤填的，请改一下体重';

    // 160cm / 200kg → BMI 78.1 > 35（典型「按斤填」异常）→ 提示行。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '160',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '200',
    );
    await tester.pump();
    expect(find.text('78.1'), findsOneWidget);
    expect(find.text(hint), findsOneWidget);

    // 边界：BMI 恰好 35.0（160cm / 89.6kg）不触发。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '89.6',
    );
    await tester.pump();
    expect(find.text('35.0'), findsOneWidget);
    expect(find.text(hint), findsNothing);

    // 回到正常体重 → 提示行消失。
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '60',
    );
    await tester.pump();
    expect(find.text(hint), findsNothing);
  });
}

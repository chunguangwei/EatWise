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
}

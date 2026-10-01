import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/legal/application/legal_providers.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
import 'package:eatwise/features/legal/presentation/legal_pages.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show photoPickerGatewayProvider;
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:eatwise/features/settings/presentation/settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/fake_http_adapter.dart';

/// 设置页（M7 + 合规 D-18）：分组渲染、语言/主题切换即时生效、
/// 健康数据授权撤回、数据分析授权接 ConsentStore、U3 导出 / U5 删除 /
/// U6 撤销 / U1 账号标识（D-13 v2：username 优先，其次脱敏手机号）、双语。
void main() {
  late SharedPreferences prefs;
  late FakeHttpAdapter adapter;
  late AuthGate authGate;
  late InMemoryTokenStore tokenStore;
  late InMemoryPrivacyConsentStore privacyStore;
  late InMemoryConsentStore consentStore;
  late _FakeExportService exportService;
  late _FakeDeletionService deletionService;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    adapter = FakeHttpAdapter();
    authGate = AuthGate()..loggedIn = true;
    tokenStore = InMemoryTokenStore();
    privacyStore = InMemoryPrivacyConsentStore()..hasAgreedCurrentPolicy = true;
    consentStore = InMemoryConsentStore();
    exportService = _FakeExportService();
    deletionService = _FakeDeletionService();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: <RouteBase>[
        GoRoute(
          path: '/profile',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/legal/privacy',
          builder: (context, state) {
            final t = Translations.of(context);
            return LegalDocumentPage(
              title: t.legal.privacyPolicy.title,
              body: t.legal.privacyPolicy.body,
            );
          },
        ),
        GoRoute(
          path: '/legal/agreement',
          builder: (context, state) {
            final t = Translations.of(context);
            return LegalDocumentPage(
              title: t.legal.userAgreement.title,
              body: t.legal.userAgreement.body,
            );
          },
        ),
        GoRoute(
          path: '/legal/disclaimer',
          builder: (context, state) => const DisclaimerPage(),
        ),
      ],
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            privacyConsentStoreProvider.overrideWithValue(privacyStore),
            privacyGateProvider.overrideWithValue(PrivacyGate(agreed: true)),
            consentStoreProvider.overrideWithValue(consentStore),
            analyticsClientsProvider.overrideWithValue(const []),
            tokenStoreProvider.overrideWithValue(tokenStore),
            authGateProvider.overrideWithValue(authGate),
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
            dataExportServiceProvider.overrideWithValue(exportService),
            accountDeletionServiceProvider.overrideWithValue(deletionService),
            ...extraOverrides,
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120);
    await tester.pump();
  }

  testWidgets('分组渲染：四组卡（身体与目标/账号与安全/数据与AI/关于与法务）与关键行齐备', (tester) async {
    await pumpSettings(tester);

    expect(find.text('设置'), findsOneWidget);
    // 资料头卡（圆形头像占位 + 「账号」小标签）。
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.text('身体与目标'), findsOneWidget);
    expect(find.text('身体档案'), findsOneWidget);
    expect(find.text('健康数据授权'), findsOneWidget);
    expect(find.text('通知设置'), findsOneWidget);
    // 组标题「账号与安全」与危险行（头卡加高后落在首屏外，先滚动）。
    await scrollTo(tester, find.text('账号与安全'));
    expect(find.text('账号与安全'), findsOneWidget);
    await scrollTo(tester, find.text('删除账号'));
    expect(find.text('删除账号'), findsOneWidget);

    // 数据与 AI 组（视口外先滚动）。
    await scrollTo(tester, find.text('数据与 AI'));
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('导出我的数据'), findsOneWidget);
    expect(find.text('数据分析授权'), findsOneWidget);

    // 关于与法务组（协议四项收敛进「协议与说明」合并入口）。
    await scrollTo(tester, find.text('关于与法务'));
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('协议与说明'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('语言切换即时生效并持久化（D-15）', (tester) async {
    await pumpSettings(tester);
    expect(find.text('设置'), findsOneWidget);

    // 账号区新增行后语言行可能落在视口外，先滚动到可见。
    await scrollTo(tester, find.text('语言'));
    await tester.tap(find.text('语言'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 全树文案立即切英文，无需重启。
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Data & AI'), findsOneWidget);
    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(prefs.getString('settings.languageMode'), 'en');

    await unmount(tester);
  });

  testWidgets('主题切换即时生效并持久化（亮/暗/跟随系统）', (tester) async {
    final container = await pumpSettings(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);
    // 账号区新增「修改密码」行后主题行落在视口外，先滚动到可见。
    await scrollTo(tester, find.text('主题'));
    await tester.tap(find.text('主题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('深色'));
    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(prefs.getString('settings.themeMode'), 'dark');

    await unmount(tester);
  });

  testWidgets('数据分析授权开关接 ConsentStore：授权采集、撤回 suppressed', (tester) async {
    await pumpSettings(tester);
    expect(consentStore.analyticsGranted, isFalse);

    // 三个 Switch：①喝水提醒 ②健康数据授权 ③数据分析授权。ListView 懒
    // 构建会回收视口外行——先按文案滚到「数据分析授权」行，再取当前树内
    // 最后一个 Switch（滚出视口的喝水提醒行已被回收，不能用固定下标）。
    await scrollTo(tester, find.text('数据分析授权'));
    final analyticsSwitch = find.byType(Switch).last;
    await tester.tap(analyticsSwitch);
    await tester.pump();
    await tester.pump();
    expect(consentStore.analyticsGranted, isTrue);

    // 撤回 → 停止采集（ConsentStore 回落 false）。
    await tester.tap(analyticsSwitch);
    await tester.pump();
    await tester.pump();
    expect(consentStore.analyticsGranted, isFalse);

    await unmount(tester);
  });

  testWidgets('撤回健康数据单独授权（§4.4）', (tester) async {
    privacyStore.healthDataGranted = true;
    await pumpSettings(tester);

    // Switch 顺序（UI 重构后）：①喝水提醒 ②健康数据授权 ③数据分析授权。
    final healthSwitch = find.byType(Switch).at(1);
    expect(tester.widget<Switch>(healthSwitch).value, isTrue);

    await tester.tap(healthSwitch);
    await tester.pump();
    await tester.pump();
    expect(privacyStore.healthDataGranted, isFalse);
    expect(find.textContaining('已撤回健康数据授权'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('导出数据走 U3：返回服务端聚合 JSON 保存路径并提示', (tester) async {
    await pumpSettings(tester);

    await scrollTo(tester, find.text('导出我的数据'));
    await tester.tap(find.text('导出我的数据'));
    await tester.pump();
    await tester.pump();
    expect(exportService.calls, 1);
    expect(find.textContaining('数据已导出'), findsOneWidget);
    expect(
      find.textContaining('/tmp/eatwise_data_export_20260729.json'),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('删除账号：确认 → U5 申请 → 冷静期弹窗显示截止日期 → 登出', (tester) async {
    adapter.stub('/auth/logout', StubResponse.json(200, <String, Object?>{}));
    await pumpSettings(tester);

    await scrollTo(tester, find.text('删除账号'));
    await tester.tap(find.text('删除账号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 确认弹窗明示后果与冷静期。
    expect(find.textContaining('7 天冷静期'), findsOneWidget);

    await tester.tap(find.text('确认删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deletionService.calls, 1);
    // 冷静期弹窗：显示截止日期与「重新登录即可撤销」。
    expect(find.textContaining('重新登录即可撤销'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(authGate.loggedIn, isFalse);
    expect(find.textContaining('删除申请已提交'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('账号区显示 U1 脱敏手机号（phone 账号）', (tester) async {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{
            'id': 'u-1',
            'username': null,
            'phone': '+8613****8000',
            'deletionStatus': null,
            'scheduledDeletionAt': null,
          },
        }),
      ),
    );
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('+8613****8000'), findsOneWidget);
    // 成功拉取即写入本地缓存（离线兜底数据源）。
    expect(prefs.getString(AccountIdentityStore.key), '+8613****8000');

    await unmount(tester);
  });

  testWidgets('账号区显示 username（D-13 v2 账号密码主路径优先）', (tester) async {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{
            'id': 'u-2',
            'username': 'wcg',
            'phone': null,
            'deletionStatus': null,
            'scheduledDeletionAt': null,
          },
        }),
      ),
    );
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('wcg'), findsOneWidget);
    expect(find.text('未登录'), findsNothing);
    // 缓存内容为实际显示值（username 优先于脱敏手机号）。
    expect(prefs.getString(AccountIdentityStore.key), 'wcg');

    await unmount(tester);
  });

  testWidgets('账号标识兜底：U1 失败但有本地缓存时显示缓存标识', (tester) async {
    await prefs.setString(AccountIdentityStore.key, '+8613****8000');
    // U1 接口失败（断网）→ userMeProvider 回落 null。
    adapter.stub('/users/me', StubResponse.networkError('offline'));
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('+8613****8000'), findsOneWidget);
    expect(find.text('未登录'), findsNothing);

    await unmount(tester);
  });

  // v1.13.13 契约：已登录（restore 成功）但 U1 失败/标识为空时不再显
  // 「未登录」（与登录态矛盾），改「点击重试」；原始 userId 永不上屏。
  testWidgets('账号标识兜底：已登录且 U1 失败时显示点击重试（不回退展示原始 userId）', (tester) async {
    const uuid = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
    await tokenStore.saveTokens(
      accessToken: 'a-test',
      refreshToken: 'r-test',
      userId: uuid,
    );
    // U1 接口失败（断网）→ userMeProvider 回落 null。
    adapter.stub('/users/me', StubResponse.networkError('offline'));
    final container = await pumpSettings(tester);
    // 恢复会话：authState.userId 有值（旧逻辑会把它当手机号行兜底上屏）。
    await container.read(authControllerProvider.notifier).restore();
    await tester.pumpAndSettle();

    expect(find.text('点击重试'), findsOneWidget);
    expect(find.text('未登录'), findsNothing);
    expect(find.text(uuid), findsNothing);

    await unmount(tester);
  });

  testWidgets('登出后清除账号标识本地缓存', (tester) async {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{
            'id': 'u-1',
            'phone': '+8613****8000',
            'deletionStatus': null,
            'scheduledDeletionAt': null,
          },
        }),
      ),
    );
    adapter.stub('/auth/logout', StubResponse.json(200, <String, Object?>{}));
    await pumpSettings(tester);
    await tester.pumpAndSettle();
    // U1 成功已写入缓存。
    expect(prefs.getString(AccountIdentityStore.key), '+8613****8000');

    await scrollTo(tester, find.text('登出'));
    await tester.tap(find.text('登出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 确认弹窗按钮文案为「退出登录」（t.auth.logout，与行标题「登出」不同）。
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(authGate.loggedIn, isFalse);
    expect(prefs.getString(AccountIdentityStore.key), isNull);

    await unmount(tester);
  });

  // 走查（iOS 重装清 Keychain 会话丢失）：未登录态不得出现登出/删除账号/
  // 修改密码死路入口，改为「登录」入口。
  testWidgets('未登录态：隐藏登出/删除账号/修改密码，显示登录入口', (tester) async {
    authGate.loggedIn = false;
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('登出'), findsNothing);
    expect(find.text('删除账号'), findsNothing);
    expect(find.text('修改密码'), findsNothing);
    // 头卡加高后「登录」行落在首屏外，先滚动（未登录占位在头卡上）。
    expect(find.text('未登录'), findsOneWidget);
    await scrollTo(tester, find.text('登录'));
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('冷静期内账号：显示删除预约状态，撤销（U6）后提示并刷新', (tester) async {
    Map<String, Object?> meEnvelope(String? status) {
      return StubResponse.envelope(<String, Object?>{
        'user': <String, Object?>{
          'id': 'u-1',
          'phone': '+8613****8000',
          'deletionStatus': status,
          'scheduledDeletionAt': status == 'pending'
              ? DateTime.now()
                    .add(const Duration(days: 7))
                    .toUtc()
                    .toIso8601String()
              : null,
        },
      });
    }

    adapter.stub('/users/me', StubResponse.json(200, meEnvelope('pending')));
    adapter.stub(
      '/users/me/deletion',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'deletionStatus': null,
          'scheduledDeletionAt': null,
          'coolingOffDays': 7,
        }),
      ),
    );
    // 撤销后 invalidate 重新拉取：状态已清除。
    adapter.stub('/users/me', StubResponse.json(200, meEnvelope(null)));
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    // 头卡加高后状态行落在首屏外，先滚动到可见。
    await scrollTo(tester, find.textContaining('删除已预约'));
    expect(find.textContaining('删除已预约'), findsOneWidget);

    await scrollTo(tester, find.text('撤销删除'));
    await tester.tap(find.text('撤销删除'));
    await tester.pumpAndSettle();
    expect(deletionService.cancelCalls, 1);
    expect(find.textContaining('已撤销删除申请'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('隐私协议入口：协议与说明 → 查看隐私政策全文', (tester) async {
    await pumpSettings(tester);

    await scrollTo(tester, find.text('协议与说明'));
    await tester.tap(find.text('协议与说明'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('隐私政策'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('生效日期'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('关于区版本号读 package_info_plus（注入值上屏，非硬编码）', (tester) async {
    await pumpSettings(
      tester,
      extraOverrides: <Override>[
        appVersionLabelProvider.overrideWith((ref) async => '1.2.3 (4)'),
      ],
    );

    await scrollTo(tester, find.text('1.2.3 (4)'));
    expect(find.text('1.2.3 (4)'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsNothing); // 旧硬编码版本不再出现

    await unmount(tester);
  });

  testWidgets('头像更换：登录态点头像弹来源选择，相册上传全链路回写 avatarUrl', (tester) async {
    Map<String, Object?> userJson(String? avatarUrl) => <String, Object?>{
      'id': 'u-1',
      'username': 'wcg',
      'phone': null,
      'avatarUrl': avatarUrl,
      'deletionStatus': null,
      'scheduledDeletionAt': null,
    };
    // 初次 GET /users/me（无头像）。
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{'user': userJson(null)}),
      ),
    );
    await pumpSettings(
      tester,
      extraOverrides: <Override>[
        photoPickerGatewayProvider.overrideWithValue(_FakeAvatarPicker()),
      ],
    );
    await tester.pumpAndSettle();

    // 入口：头像带相机角标，点击弹来源选择。
    await tester.tap(
      find.byKey(const ValueKey<String>('settings.avatar.edit')),
    );
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);

    // 上传链：POST /uploads 201 → PATCH /users/me → 失效后重拉 GET。
    adapter.stub(
      '/uploads',
      StubResponse.json(
        201,
        StubResponse.envelope(<String, Object?>{
          'id': 'abc.jpg',
          'url': '/v1/uploads/abc.jpg',
        }),
      ),
    );
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': userJson('/v1/uploads/abc.jpg'),
        }),
      ),
    );
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': userJson('/v1/uploads/abc.jpg'),
        }),
      ),
    );
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('头像已更新'), findsOneWidget);
    final patchIdx = adapter.requests.indexWhere(
      (r) => r.path == '/users/me' && r.method == 'PATCH',
    );
    expect(patchIdx, greaterThanOrEqualTo(0));
    expect(
      (adapter.requestBodies[patchIdx]! as Map<String, dynamic>)['avatarUrl'],
      '/v1/uploads/abc.jpg',
    );

    await unmount(tester);
  });

  testWidgets('头像更换：相册权限被拒 → 降级弹窗引导去设置', (tester) async {
    adapter.stub(
      '/users/me',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, Object?>{
          'user': <String, Object?>{'id': 'u-1', 'username': 'wcg'},
        }),
      ),
    );
    await pumpSettings(
      tester,
      extraOverrides: <Override>[
        photoPickerGatewayProvider.overrideWithValue(_DeniedAvatarPicker()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings.avatar.edit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('无法访问照片'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('英文渲染（双语，D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    // 资料头卡（圆形头像占位，头卡替代原账号行）。
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    // 组标题 Account & Security（第二组，视口外先滚动）。
    await scrollTo(tester, find.text('Account & Security'));
    expect(find.text('Account & Security'), findsOneWidget);
    expect(find.text('Export my data'), findsOneWidget);

    await unmount(tester);
  });
}

class _FakeExportService implements DataExportService {
  int calls = 0;

  @override
  Future<String> requestExport() async {
    calls++;
    return '/tmp/eatwise_data_export_20260729.json';
  }
}

class _FakeDeletionService implements AccountDeletionService {
  int calls = 0;
  int cancelCalls = 0;

  @override
  Future<AccountDeletionView> requestDeletion() async {
    calls++;
    return AccountDeletionView(
      deletionStatus: 'pending',
      scheduledDeletionAt: DateTime.now().add(const Duration(days: 7)),
    );
  }

  @override
  Future<AccountDeletionView> cancelDeletion() async {
    cancelCalls++;
    return const AccountDeletionView();
  }
}

/// 头像取图桩：固定返回最小 PNG 魔数字节（上传链只认字节流）。
final class _FakeAvatarPicker implements PhotoPickerGateway {
  @override
  Future<Uint8List?> pick(PhotoSource source) async =>
      Uint8List.fromList(const <int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
}

/// 头像取图桩：模拟系统权限拒绝（走 §4.3 降级弹窗）。
final class _DeniedAvatarPicker implements PhotoPickerGateway {
  @override
  Future<Uint8List?> pick(PhotoSource source) =>
      throw PhotoPermissionDeniedException(source);
}

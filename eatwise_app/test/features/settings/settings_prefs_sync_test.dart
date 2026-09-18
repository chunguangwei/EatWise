import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/account/application/weight_unit_controller.dart';
import 'package:eatwise/features/account/domain/weight_unit.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/application/settings_prefs_sync.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-21 用户级偏好跨端同步：协调器单测（dio HttpClientAdapter 桩，
/// 不打真实网络；UserApi 直接读解包后 data，桩返回信封内层）。

/// 按路径返回桩响应的 HttpClientAdapter（记录请求供断言）。
final class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.routes);

  /// path → 依次消费的响应体（已解包 data 层）；值为 null 表示网络错误。
  final Map<String, List<Object?>> routes;

  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Object?> bodies = <Object?>[];

  int patches() => requests
      .where((r) => r.method == 'PATCH' && r.path == '/users/me')
      .length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(options.data);
    final queue = routes[options.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('StubAdapter: 未注册响应 ${options.path}');
    }
    final body = queue.removeAt(0);
    if (body == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  UserApi apiOf(StubAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://stub'));
    dio.httpClientAdapter = adapter;
    return UserApi(dio);
  }

  Map<String, dynamic> meJson(Map<String, dynamic>? settingsPrefs) {
    return <String, dynamic>{
      'user': <String, dynamic>{'id': 'u1', 'settingsPrefs': ?settingsPrefs},
    };
  }

  group('SettingsPrefsSync（纯协调器，假 collect/apply）', () {
    late StubAdapter adapter;
    late List<Map<String, dynamic>> applied;
    late DateTime? storedSyncedAt;
    late bool loggedIn;
    late Map<String, Object?> local;

    SettingsPrefsSync build({DateTime Function()? now}) {
      return SettingsPrefsSync(
        api: apiOf(adapter),
        isLoggedIn: () => loggedIn,
        collectLocal: () => local,
        applyRemote: applied.add,
        readLastSyncedAt: () => storedSyncedAt,
        saveLastSyncedAt: (at) async => storedSyncedAt = at,
        now: now,
      );
    }

    setUp(() {
      adapter = StubAdapter(<String, List<Object?>>{});
      applied = <Map<String, dynamic>>[];
      storedSyncedAt = null;
      loggedIn = true;
      local = <String, Object?>{
        'locale': 'zh-CN',
        'theme': 'system',
        'weightUnit': 'kg',
        'burnGoalKcal': 200.0,
        'stepsGoal': 5000,
      };
    });

    test('push：整包 PATCH 带 syncedAt，成功后记录 lastSyncedAt', () async {
      adapter.routes['/users/me'] = <Object?>[meJson(null)];
      final now = DateTime.utc(2026, 9, 18, 8);
      await build(now: () => now).push();

      expect(adapter.patches(), 1);
      final body = adapter.bodies.single as Map<String, dynamic>;
      final prefs = body['settingsPrefs'] as Map<String, dynamic>;
      expect(prefs, <String, Object?>{
        'locale': 'zh-CN',
        'theme': 'system',
        'weightUnit': 'kg',
        'burnGoalKcal': 200.0,
        'stepsGoal': 5000,
        'syncedAt': '2026-09-18T08:00:00.000Z',
      });
      expect(storedSyncedAt, now);
    });

    test('push：未登录 no-op；网络失败静默不抛', () async {
      loggedIn = false;
      await build().push();
      expect(adapter.requests, isEmpty);

      loggedIn = true;
      adapter.routes['/users/me'] = <Object?>[null]; // 网络错误
      await expectLater(build().push(), completes);
      expect(storedSyncedAt, isNull); // 失败不记录时间戳
    });

    test('pull：远端 settingsPrefs 为空 → 不应用', () async {
      adapter.routes['/users/me'] = <Object?>[meJson(null)];
      await build().pull();
      expect(applied, isEmpty);

      adapter.routes['/users/me'] = <Object?>[meJson(<String, dynamic>{})];
      await build().pull();
      expect(applied, isEmpty);
    });

    test('pull：远端 syncedAt 不新于本地 → 不覆盖', () async {
      storedSyncedAt = DateTime.utc(2026, 9, 18, 9);
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'syncedAt': '2026-09-18T08:00:00.000Z', // 比本地旧
        }),
      ];
      await build().pull();
      expect(applied, isEmpty);

      // 同时刻也不算更新（字段级 LWW 以本地记录为准）。
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      await build().pull();
      expect(applied, isEmpty);
    });

    test('pull：远端无 syncedAt 且本地已有记录 → 不应用', () async {
      storedSyncedAt = DateTime.utc(2026, 9, 18, 9);
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{'theme': 'dark'}),
      ];
      await build().pull();
      expect(applied, isEmpty);
    });

    test('pull：远端更新 → 应用并记录远端 syncedAt', () async {
      storedSyncedAt = DateTime.utc(2026, 9, 18, 8);
      final remote = <String, dynamic>{
        'theme': 'dark',
        'syncedAt': '2026-09-18T09:30:00.000Z',
      };
      adapter.routes['/users/me'] = <Object?>[meJson(remote)];
      await build().pull();
      expect(applied, <Map<String, dynamic>>[remote]);
      expect(storedSyncedAt, DateTime.utc(2026, 9, 18, 9, 30));
    });

    test('回环防护：applying 期间 push 直接跳过', () async {
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      // apply 回调里模拟「setter 触发 push」：此时 applying=true，
      // push 必须跳过（不应再发 PATCH）。
      late SettingsPrefsSync guarded;
      Future<void> applyThenPush(Map<String, dynamic> prefs) async {
        applied.add(prefs);
        expect(guarded.applying, isTrue);
        await guarded.push();
      }

      guarded = SettingsPrefsSync(
        api: apiOf(adapter),
        isLoggedIn: () => true,
        collectLocal: () => local,
        applyRemote: (p) => applyThenPush(p),
        readLastSyncedAt: () => null,
        saveLastSyncedAt: (at) async => storedSyncedAt = at,
      );
      await guarded.pull();
      expect(applied, hasLength(1));
      expect(adapter.patches(), 0);
      expect(guarded.applying, isFalse); // 结束后复位
    });

    test('pull：网络失败静默不抛', () async {
      adapter.routes['/users/me'] = <Object?>[null];
      await expectLater(build().pull(), completes);
      expect(applied, isEmpty);
    });
  });

  group('settingsPrefsSyncProvider（真实接线）', () {
    late SharedPreferences prefs;
    late StubAdapter adapter;
    late ProviderContainer container;

    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    Future<void> setUpContainer({
      Map<String, Object> initialPrefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(initialPrefs);
      prefs = await SharedPreferences.getInstance();
      adapter = StubAdapter(<String, List<Object?>>{});
      final tokenStore = InMemoryTokenStore();
      await tokenStore.saveTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        userId: 'u1',
      );
      container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(tokenStore),
          authGateProvider.overrideWithValue(AuthGate()),
          apiDioProvider.overrideWith((ref) {
            final dio = createApiDio(tokenStore: tokenStore);
            dio.httpClientAdapter = adapter;
            return dio;
          }),
        ],
      );
      addTearDown(container.dispose);
      // 有 refreshToken → 恢复会话为登录态。
      await container.read(authControllerProvider.notifier).restore();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.loggedIn,
      );
    }

    test('collect 键约定 + setter 变更触发整包 push', () async {
      await setUpContainer();
      // Provider 懒加载：先实例化（生产中由 main/登录挂接点的 pull 触发），
      // ref.listen 挂接的「setter 变更 → push」才生效。
      container.read(settingsPrefsSyncProvider);
      // 前三次 setter 各触发一次 push（先垫好响应并等它们落地，避免与
      // 后面的单次断言抢时序）。
      adapter.routes['/users/me'] = <Object?>[
        meJson(null),
        meJson(null),
        meJson(null),
      ];
      container.read(languageModeProvider.notifier).setMode('en');
      container.read(weightUnitProvider.notifier).setUnit(WeightUnit.jin);
      await container.read(exerciseGoalsProvider.notifier).setStepsGoal(8000);
      await flush();
      expect(adapter.patches(), 3);
      // 清掉记录后单看一次变更的包体。
      adapter.requests.clear();
      adapter.bodies.clear();
      adapter.routes['/users/me'] = <Object?>[meJson(null)];

      container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await flush();

      expect(adapter.patches(), 1);
      final body = adapter.bodies.single as Map<String, dynamic>;
      final prefsBody = body['settingsPrefs'] as Map<String, dynamic>;
      expect(prefsBody['locale'], 'en');
      expect(prefsBody['theme'], 'dark');
      expect(prefsBody['weightUnit'], 'jin');
      expect(prefsBody['burnGoalKcal'], 200);
      expect(prefsBody['stepsGoal'], 8000);
      expect(prefsBody['syncedAt'], isA<String>());
      expect(prefs.getString(lastPrefsSyncedAtKey), isNotNull);
    });

    test('pull：远端新 → 应用到本地 provider，缺键不动，且不触发回推', () async {
      await setUpContainer(
        initialPrefs: <String, Object>{
          lastPrefsSyncedAtKey: '2026-09-18T08:00:00.000Z',
        },
      );
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'weightUnit': 'jin',
          'stepsGoal': 9000,
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      await container.read(settingsPrefsSyncProvider).pull();
      await flush();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(container.read(weightUnitProvider), WeightUnit.jin);
      expect(container.read(exerciseGoalsProvider).stepsGoal, 9000);
      // 缺键项不动（默认 system 语言 / kg 默认消耗目标）。
      expect(container.read(languageModeProvider), 'system');
      expect(container.read(exerciseGoalsProvider).burnGoalKcal, 200);
      // 回环防护：pull 应用触发的 setter 变更没有回推 PATCH。
      expect(adapter.patches(), 0);
      expect(prefs.getString(lastPrefsSyncedAtKey), '2026-09-18T09:00:00.000Z');
    });

    test('pull：远端 syncedAt 比本地旧 → 不覆盖本地偏好', () async {
      await setUpContainer(
        initialPrefs: <String, Object>{
          lastPrefsSyncedAtKey: '2026-09-18T10:00:00.000Z',
        },
      );
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      await container.read(settingsPrefsSyncProvider).pull();
      await flush();

      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(adapter.patches(), 0);
    });

    test('pull：非法/不识别值忽略，其余键照常应用', () async {
      await setUpContainer();
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'blue', // 非法
          'weightUnit': 'jin',
          'stepsGoal': 10, // 低于下限
          'burnGoalKcal': 500,
          'futureNewKey': 'ignored', // 未来新增键：跳过
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      await container.read(settingsPrefsSyncProvider).pull();
      await flush();

      expect(container.read(themeModeProvider), ThemeMode.system); // 未动
      expect(container.read(weightUnitProvider), WeightUnit.jin);
      expect(container.read(exerciseGoalsProvider).stepsGoal, 5000); // 未动
      expect(container.read(exerciseGoalsProvider).burnGoalKcal, 500);
    });
  });
}

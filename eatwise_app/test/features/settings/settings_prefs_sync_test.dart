import 'dart:async';
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
  Future<void> Function(RequestOptions options)? beforeRespond;

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
    await beforeRespond?.call(options);
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

  Map<String, dynamic> meJson(
    Map<String, dynamic>? settingsPrefs, {
    String id = 'u1',
  }) {
    return <String, dynamic>{
      'user': <String, dynamic>{'id': id, 'settingsPrefs': ?settingsPrefs},
    };
  }

  group('SettingsPrefsSync（纯协调器，假 collect/apply）', () {
    late StubAdapter adapter;
    late List<Map<String, dynamic>> applied;
    late DateTime? storedSyncedAt;
    late Map<String, DateTime> syncedAtByUser;
    late Map<String, String> dirtyByUser;
    late String currentUserId;
    late bool loggedIn;
    late Map<String, Object?> local;

    SettingsPrefsSync build({DateTime Function()? now}) {
      return SettingsPrefsSync(
        api: apiOf(adapter),
        isLoggedIn: () => loggedIn,
        userId: () => currentUserId,
        collectLocal: () => local,
        applyRemote: applied.add,
        readDirtyPayload: (uid) => dirtyByUser[uid],
        saveDirtyPayload: (uid, payload) async {
          if (payload == null) {
            dirtyByUser.remove(uid);
          } else {
            dirtyByUser[uid] = payload;
          }
        },
        readLastSyncedAt: (uid) =>
            syncedAtByUser[uid] ?? (uid == 'u1' ? storedSyncedAt : null),
        saveLastSyncedAt: (uid, at) async {
          syncedAtByUser[uid] = at;
          if (uid == 'u1') storedSyncedAt = at;
        },
        now: now,
      );
    }

    setUp(() {
      adapter = StubAdapter(<String, List<Object?>>{});
      applied = <Map<String, dynamic>>[];
      storedSyncedAt = null;
      syncedAtByUser = <String, DateTime>{};
      dirtyByUser = <String, String>{};
      currentUserId = 'u1';
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

    test('push：未登录 no-op；失败保留快照，flushDirty 重试成功', () async {
      final sync = build();
      loggedIn = false;
      await sync.push();
      expect(adapter.requests, isEmpty);
      expect(dirtyByUser, isEmpty);

      loggedIn = true;
      adapter.routes['/users/me'] = <Object?>[null];
      await expectLater(sync.push(), completes);
      expect(storedSyncedAt, isNull);
      expect(dirtyByUser['u1'], isNotNull);

      adapter.routes['/users/me'] = <Object?>[meJson(null)];
      await sync.flushDirty();
      expect(dirtyByUser['u1'], isNull);
      expect(adapter.patches(), 2);
    });

    test('上行基线按 uid 隔离，互不清空对方状态', () async {
      final sync = build();
      adapter.routes['/users/me'] = <Object?>[meJson(null)];
      await sync.push();
      final firstBaseline = syncedAtByUser['u1'];

      currentUserId = 'u2';
      local = <String, Object?>{...local, 'theme': 'dark'};
      adapter.routes['/users/me'] = <Object?>[meJson(null, id: 'u2')];
      await sync.push();

      expect(syncedAtByUser['u1'], firstBaseline);
      expect(syncedAtByUser['u2'], isNotNull);
      expect(dirtyByUser, isEmpty);
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
        userId: () => currentUserId,
        collectLocal: () => local,
        applyRemote: (p) => applyThenPush(p),
        readDirtyPayload: (uid) => dirtyByUser[uid],
        saveDirtyPayload: (uid, payload) async {
          if (payload == null) {
            dirtyByUser.remove(uid);
          } else {
            dirtyByUser[uid] = payload;
          }
        },
        readLastSyncedAt: (uid) => null,
        saveLastSyncedAt: (uid, at) async => storedSyncedAt = at,
      );
      await guarded.pull();
      expect(applied, hasLength(1));
      expect(adapter.patches(), 0);
      expect(guarded.applying, isFalse); // 结束后复位
    });

    test('pull：本地有待上行快照时优先本地，不发 GET', () async {
      dirtyByUser['u1'] = '{"theme":"light"}';
      await build().pull();
      expect(adapter.requests, isEmpty);
      expect(applied, isEmpty);
      expect(dirtyByUser['u1'], isNotNull);
    });

    test('pull：旧账号的迟到响应不写入新账号', () async {
      final sync = build();
      final started = Completer<void>();
      final release = Completer<void>();
      adapter.routes['/users/me'] = <Object?>[
        meJson(<String, dynamic>{
          'theme': 'dark',
          'syncedAt': '2026-09-18T09:00:00.000Z',
        }),
      ];
      adapter.beforeRespond = (options) async {
        if (options.method == 'GET') {
          started.complete();
          await release.future;
        }
      };

      final pulling = sync.pull();
      await started.future;
      currentUserId = 'u2';
      release.complete();
      await pulling;

      expect(applied, isEmpty);
      expect(syncedAtByUser, isEmpty);
      expect(storedSyncedAt, isNull);
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
      await flush();
      container.read(weightUnitProvider.notifier).setUnit(WeightUnit.jin);
      await flush();
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
      expect(prefs.getString(lastPrefsSyncedAtKeyFor('u1')), isNotNull);
    });

    test('pull：远端新 → 应用到本地 provider，缺键不动，且不触发回推', () async {
      await setUpContainer(
        initialPrefs: <String, Object>{
          lastPrefsSyncedAtKeyFor('u1'): '2026-09-18T08:00:00.000Z',
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
      expect(
        prefs.getString(lastPrefsSyncedAtKeyFor('u1')),
        '2026-09-18T09:00:00.000Z',
      );
    });

    test('pull：远端 syncedAt 比本地旧 → 不覆盖本地偏好', () async {
      await setUpContainer(
        initialPrefs: <String, Object>{
          lastPrefsSyncedAtKeyFor('u1'): '2026-09-18T10:00:00.000Z',
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

  group('userMe 会话边界', () {
    test('uid 切换使视图失效，A 的管理员/头像慢响应不写入 B', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final tokenStore = InMemoryTokenStore();
      final gate = AuthGate();
      final responses = <Map<String, dynamic>>[
        <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u-A',
            'username': 'user-A',
            'avatarUrl': '/a.png',
            'role': 'admin',
          },
        },
        <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u-B',
            'username': 'user-B',
            'avatarUrl': '/b.png',
            'role': 'user',
          },
        },
      ];
      final adapter = StubAdapter(<String, List<Object?>>{});
      final gates = <Completer<void>>[Completer<void>(), Completer<void>()];
      var requestIndex = 0;
      adapter.beforeRespond = (options) {
        final index = requestIndex++;
        adapter.routes[options.path] = <Object?>[responses[index]];
        return gates[index].future;
      };
      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(tokenStore),
          authGateProvider.overrideWithValue(gate),
          apiDioProvider.overrideWithValue(Dio()),
          userApiProvider.overrideWithValue(apiOf(adapter)),
        ],
      );
      addTearDown(container.dispose);
      await tokenStore.saveTokens(
        accessToken: 'at-A',
        refreshToken: 'rt-A',
        userId: 'u-A',
      );
      await container.read(authControllerProvider.notifier).restore();
      final aFuture = container.read(userMeProvider.future);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));

      await tokenStore.saveTokens(
        accessToken: 'at-B',
        refreshToken: 'rt-B',
        userId: 'u-B',
      );
      await container.read(authControllerProvider.notifier).restore();
      final bFuture = container.read(userMeProvider.future);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2));
      gates[1].complete();
      expect((await bFuture)!.id, 'u-B');

      gates[0].complete();
      await aFuture;
      final current = await container.read(userMeProvider.future);
      expect(current!.id, 'u-B');
      expect(current.role, 'user');
      expect(current.avatarUrl, '/b.png');
      expect(prefs.getString(AccountIdentityStore.keyFor('u-B')), 'user-B');
      expect(prefs.getString(AccountIdentityStore.keyFor('u-A')), isNull);
    });

    test('A→匿名→A 后旧 A 响应不覆盖新 A 的头像与账号缓存', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final tokenStore = InMemoryTokenStore();
      final gate = AuthGate();
      final responses = <Map<String, dynamic>>[
        <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u-A',
            'username': 'old-A',
            'avatarUrl': '/old-a.png',
            'role': 'admin',
          },
        },
        <String, dynamic>{
          'user': <String, dynamic>{
            'id': '',
            'username': 'anonymous-session',
            'role': 'admin',
          },
        },
        <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u-A',
            'username': 'new-A',
            'avatarUrl': '/new-a.png',
            'role': 'user',
          },
        },
      ];
      final adapter = StubAdapter(<String, List<Object?>>{});
      final gates = List<Completer<void>>.generate(3, (_) => Completer<void>());
      var requestIndex = 0;
      adapter.beforeRespond = (options) {
        final index = requestIndex++;
        adapter.routes[options.path] = <Object?>[responses[index]];
        return gates[index].future;
      };
      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(tokenStore),
          authGateProvider.overrideWithValue(gate),
          apiDioProvider.overrideWithValue(Dio()),
          userApiProvider.overrideWithValue(apiOf(adapter)),
        ],
      );
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await tokenStore.saveTokens(
        accessToken: 'at-old-A',
        refreshToken: 'rt-old-A',
        userId: 'u-A',
      );
      await auth.restore();
      final oldFuture = container.read(userMeProvider.future);
      await pumpEventQueue();

      await tokenStore.clear();
      await auth.restore();
      final anonymousFuture = container.read(userMeProvider.future);
      await pumpEventQueue();
      await tokenStore.saveTokens(
        accessToken: 'at-new-A',
        refreshToken: 'rt-new-A',
        userId: 'u-A',
      );
      await auth.restore();
      final newFuture = container.read(userMeProvider.future);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(3));

      gates[2].complete();
      expect((await newFuture)!.username, 'new-A');
      gates[0].complete();
      gates[1].complete();
      await oldFuture;
      await anonymousFuture;

      final current = await container.read(userMeProvider.future);
      expect(current!.username, 'new-A');
      expect(current.role, 'user');
      expect(current.avatarUrl, '/new-a.png');
      expect(prefs.getString(AccountIdentityStore.keyFor('u-A')), 'new-A');
    });
  });
}

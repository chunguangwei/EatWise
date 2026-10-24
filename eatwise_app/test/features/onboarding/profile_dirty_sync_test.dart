import 'dart:async';
import 'dart:convert';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 身体档案/引导状态上行脏标记制（v1.13.31）：置脏合并、即时上行清脏、
/// 失败保留下轮、匿名期脏登录迁移、坏数据清键。
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  const uid = 'u1';
  const dirtyKey = 'profile_dirty_$uid';
  const anonDirtyKey = 'profile_dirty_anonymous';

  ({RemoteProfileSyncService sync, List<Map<String, Object?>> calls}) build({
    bool loggedIn = true,
    String userId = uid,
    bool fail = false,
  }) {
    final calls = <Map<String, Object?>>[];
    final sync = RemoteProfileSyncService(
      (patch) async {
        calls.add(Map<String, Object?>.of(patch));
        if (fail) throw Exception('offline');
        return UserMeView(id: uid, username: 'u', maskedPhone: '');
      },
      () => loggedIn,
      prefs,
      () => userId,
    );
    return (sync: sync, calls: calls);
  }

  test('登录态写入：置脏 + 即时上行成功 → 清脏（compare-and-delete）', () async {
    final s = build();
    s.sync.syncOnboardingSkipped();
    await Future<void>.delayed(Duration.zero);

    expect(s.calls.single, <String, Object?>{'onboardingStatus': 'skipped'});
    expect(prefs.getString(dirtyKey), isNull);
  });

  test('上行失败：脏保留；下轮 flush 成功后清脏', () async {
    var fail = true;
    final calls = <Map<String, Object?>>[];
    UserMeView patcher(Map<String, Object?> patch) {
      calls.add(Map<String, Object?>.of(patch));
      if (fail) throw Exception('offline');
      return UserMeView(id: uid, username: 'u', maskedPhone: '');
    }

    final sync = RemoteProfileSyncService(
      (patch) async => patcher(patch),
      () => true,
      prefs,
      () => uid,
    );
    sync.syncOnboardingSkipped();
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(dirtyKey), isNotNull); // 失败保脏

    fail = false;
    await sync.flushDirty();
    expect(prefs.getString(dirtyKey), isNull);
    expect(calls, hasLength(2));
  });

  test('键级 LWW 合并：两次置脏合并为一份 patch（后写键覆盖）', () async {
    final s = build(fail: true);
    s.sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 170});
    s.sync.markDirtyAndTryFlush(const <String, Object?>{'weightKg': 65});
    s.sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 171});
    await Future<void>.delayed(Duration.zero);

    final raw = jsonDecode(prefs.getString(dirtyKey)!) as Map<String, dynamic>;
    expect(raw, <String, Object?>{'heightCm': 171, 'weightKg': 65});
  });

  test('匿名期写入只落脏不发请求；登录后 flush 迁移上行并清匿名键', () async {
    final s = build(loggedIn: false, userId: 'anonymous');
    s.sync.syncOnboardingSkipped();
    await Future<void>.delayed(Duration.zero);
    expect(s.calls, isEmpty); // 匿名 PATCH 必 401，不发
    expect(prefs.getString(anonDirtyKey), isNotNull);

    // 登录后（uid 切换）同步轮 flush：迁移 → 上行 → 双键清。
    final s2 = build();
    await s2.sync.flushDirty();
    expect(s2.calls.single, <String, Object?>{'onboardingStatus': 'skipped'});
    expect(prefs.getString(anonDirtyKey), isNull);
    expect(prefs.getString(dirtyKey), isNull);
  });

  test('脏数据损坏 / 空 patch：清键不抛', () async {
    final s = build();
    await prefs.setString(dirtyKey, 'not-json');
    await s.sync.flushDirty();
    expect(prefs.getString(dirtyKey), isNull);
    expect(s.calls, isEmpty);

    await prefs.setString(dirtyKey, '{}');
    await s.sync.flushDirty();
    expect(prefs.getString(dirtyKey), isNull);
    expect(s.calls, isEmpty);
  });

  for (final status in <int>[429, 500]) {
    test('HTTP $status：保留 dirty 且不进入退避，下轮可重试', () async {
      var reject = true;
      final calls = <Map<String, Object?>>[];
      final sync = RemoteProfileSyncService(
        (patch) async {
          calls.add(Map<String, Object?>.of(patch));
          if (reject) {
            throw BusinessApiException(
              httpStatus: status,
              code: status == 429 ? 'RATE_LIMITED' : 'INTERNAL_ERROR',
              message: 'temporary',
            );
          }
          return const UserMeView(id: uid, username: 'u', maskedPhone: '');
        },
        () => true,
        prefs,
        () => uid,
      );

      sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 170});
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      expect(prefs.getString(dirtyKey), isNotNull);
      expect(sync.hasSyncFailure, isFalse);

      reject = false;
      await sync.flushDirty();
      expect(calls, hasLength(2));
      expect(prefs.getString(dirtyKey), isNull);
    });
  }

  test('明确 400：保留 payload 并退避，手动重试才重新请求', () async {
    var reject = true;
    final calls = <Map<String, Object?>>[];
    final sync = RemoteProfileSyncService(
      (patch) async {
        calls.add(Map<String, Object?>.of(patch));
        if (reject) {
          throw const BusinessApiException(
            httpStatus: 400,
            code: 'VALIDATION_ERROR',
            message: 'invalid',
          );
        }
        return const UserMeView(id: uid, username: 'u', maskedPhone: '');
      },
      () => true,
      prefs,
      () => uid,
    );

    sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 170});
    await Future<void>.delayed(Duration.zero);
    final payload = prefs.getString(dirtyKey);
    expect(payload, isNotNull);
    expect(sync.hasSyncFailure, isTrue);
    expect(calls, hasLength(1));

    await sync.flushDirty();
    await sync.flushDirty();
    expect(calls, hasLength(1), reason: '退避中同步轮不得重复打 400');
    expect(prefs.getString(dirtyKey), payload);

    reject = false;
    final ProfileSyncService service = sync;
    await service.retryFailedNow();
    expect(calls, hasLength(2));
    expect(prefs.getString(dirtyKey), isNull);
    expect(service.hasSyncFailure, isFalse);
  });

  test('PATCH 串行 + trailing flush：在途旧值完成后新值最终胜出', () async {
    final calls = <Map<String, Object?>>[];
    final gates = <Completer<UserMeView>>[
      Completer<UserMeView>(),
      Completer<UserMeView>(),
    ];
    final sync = RemoteProfileSyncService(
      (patch) {
        calls.add(Map<String, Object?>.of(patch));
        return gates[calls.length - 1].future;
      },
      () => true,
      prefs,
      () => uid,
    );
    const me = UserMeView(id: uid, username: 'u', maskedPhone: '');

    sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 170});
    await Future<void>.delayed(Duration.zero);
    expect(calls, <Map<String, Object?>>[
      const <String, Object?>{'heightCm': 170},
    ]);

    sync.markDirtyAndTryFlush(const <String, Object?>{'heightCm': 171});
    final flushing = sync.flushDirty();
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(1), reason: '旧 PATCH 在途时不得并发发新 PATCH');

    gates[0].complete(me);
    for (var i = 0; i < 20 && calls.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls, hasLength(2));
    expect(calls.last, const <String, Object?>{'heightCm': 171});
    gates[1].complete(me);
    await flushing;

    expect(prefs.getString(dirtyKey), isNull);
    expect(calls.last, const <String, Object?>{'heightCm': 171});
  });
}

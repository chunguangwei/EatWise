import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/settings/application/settings_prefs_sync.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedPlanApi extends FastingPlanApi {
  _DelayedPlanApi() : super(Dio());
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> putCurrent(FastingPlan plan) async {
    started.complete();
    await finish.future;
  }
}

class _DelayedUserApi implements HttpClientAdapter {
  late final api = UserApi(
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))..httpClientAdapter = this,
  );
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await finish.future;
    return ResponseBody.fromString(
      '{"user":{"id":"A","username":"A","maskedPhone":""}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DelayedExtendApi extends FastingPlanApi {
  _DelayedExtendApi(this.userId, {required this.rejectLookup}) : super(Dio());

  final String Function() userId;
  final bool rejectLookup;
  final started = Completer<void>();
  final finish = Completer<void>();
  final extensions = <({String userId, String requestId, String recordId})>[];
  var _firstLookup = true;

  @override
  Future<String?> fetchActiveRecordId() async {
    if (_firstLookup) {
      _firstLookup = false;
      started.complete();
      await finish.future;
      if (rejectLookup) throw const SessionChangedException();
    }
    return 'record-A';
  }

  @override
  Future<void> extendFast({
    required String clientRequestId,
    required String recordId,
    required int extendMinutes,
  }) async {
    extensions.add((
      userId: userId(),
      requestId: clientRequestId,
      recordId: recordId,
    ));
  }
}

void main() {
  for (final rejectLookup in [false, true]) {
    test(
      'F3 session switch during lookup ${rejectLookup ? 'rejection' : 'response'} retains only A retry',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tokens = InMemoryTokenStore();
        var uid = 'A';
        await tokens.saveTokens(
          accessToken: 'a',
          refreshToken: 'ra',
          userId: uid,
        );
        final api = _DelayedExtendApi(() => uid, rejectLookup: rejectLookup);
        final sync = FastingPlanSync(
          api: api,
          prefs: prefs,
          userId: () => uid,
          captureSession: () => SessionLease(tokens),
        );
        final pending = sync.reportExtend(
          clientRequestId: 'extend-A',
          extendMinutes: 30,
        );
        await api.started.future;
        uid = 'B';
        await tokens.saveTokens(
          accessToken: 'b',
          refreshToken: 'rb',
          userId: uid,
        );
        api.finish.complete();
        await pending;
        expect(api.extensions, isEmpty);
        expect(prefs.getString('fasting_extend_pending_B'), isNull);
        final queue =
            jsonDecode(prefs.getString('fasting_extend_pending_A')!) as List;
        expect((queue.single as Map)['clientRequestId'], 'extend-A');
        await sync.flush();
        expect(api.extensions, isEmpty);
        uid = 'A';
        await tokens.saveTokens(
          accessToken: 'new-a',
          refreshToken: 'new-ra',
          userId: uid,
        );
        await sync.flush();
        expect(api.extensions, [
          (userId: 'A', requestId: 'extend-A', recordId: 'record-A'),
        ]);
        expect(prefs.getString('fasting_extend_pending_A'), isNull);
      },
    );
  }

  for (final kind in ['plan', 'profile', 'settings']) {
    test('$kind retains original dirty data after its session ends', () async {
      SharedPreferences.setMockInitialValues({
        'fasting_plan_dirty_A':
            '{"planId":"16:8","eatStartMinutes":720,"eatEndMinutes":1200}',
        'profile_dirty_A': '{"weightKg":70}',
      });
      final prefs = await SharedPreferences.getInstance();
      final tokens = InMemoryTokenStore();
      await tokens.saveTokens(accessToken: 'a', refreshToken: 'r', userId: 'A');
      final lease = SessionLease(tokens);
      final planApi = _DelayedPlanApi();
      final userApi = _DelayedUserApi();
      final dirty = <String, String>{'A': '{"theme":"dark"}'};
      Future<void> Function() action;
      if (kind == 'plan') {
        action = FastingPlanSync(
          api: planApi,
          prefs: prefs,
          userId: () => 'A',
        ).flush;
      } else if (kind == 'profile') {
        action = RemoteProfileSyncService(
          userApi.api.patchMe,
          () => true,
          prefs,
          () => 'A',
        ).flushDirty;
      } else {
        action = SettingsPrefsSync(
          api: userApi.api,
          isLoggedIn: () => true,
          userId: () => 'A',
          collectLocal: () => const {},
          applyRemote: (_) {},
          readDirtyPayload: (uid) => dirty[uid],
          saveDirtyPayload: (uid, value) async {
            if (value == null) {
              dirty.remove(uid);
            } else {
              dirty[uid] = value;
            }
          },
          readLastSyncedAt: (_) => null,
          saveLastSyncedAt: (_, _) async {},
        ).flushDirty;
      }
      final work = lease
          .run(action)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await (kind == 'plan' ? planApi.started.future : userApi.started.future);
      // Relogin as the same uid also starts a new session. UID alone is insufficient.
      await tokens.saveTokens(
        accessToken: 'new-a',
        refreshToken: 'new-r',
        userId: 'A',
      );
      (kind == 'plan' ? planApi.finish : userApi.finish).complete();
      await work;
      expect(prefs.getString('fasting_plan_dirty_A'), isNotNull);
      expect(prefs.getString('profile_dirty_A'), isNotNull);
      expect(dirty['A'], isNotNull);
    });
  }
}

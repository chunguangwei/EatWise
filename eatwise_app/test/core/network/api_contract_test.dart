import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/health/data/remote_exercise_log_sync.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/data/upload_api.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/fasting/tz_test_helper.dart';

/// 客户端→服务端写路径契约测试（2026-09-29 全量同步契约审计防线）。
///
/// 背景：putCurrent 漏传 clientRequestId → 服务端 DTO @IsUUID 400 →
/// 静默吞错 → fasting_plans 全库 0 行，e2e 手工构造 body 从未暴露。
/// 本文件用**真实客户端 API 类 + 录制适配器**捕获实际序列化的
/// method/path/body/query，逐端点断言服务端 DTO 的硬性要求（必填键、
/// UUIDv4 幂等键、枚举取值、区间上限、成对字段）——今后任何
/// 「客户端永远发不出合法请求」类漂移必在此被拦截。
void main() {
  setUpAll(() async {
    await initTestTimeZones();
  });

  // ---------- 录制适配器 ----------

  final requests = <({String method, String path, Object? data, String raw})>[];

  Object? Function(String path, Object? data)? responder;

  Dio buildDio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://contract.test'));
    dio.httpClientAdapter = _RecordingAdapter(requests, (path, data) {
      return responder?.call(path, data) ?? const <String, dynamic>{};
    });
    return dio;
  }

  ({String method, String path, Map<String, dynamic> body}) lastReq() {
    final r = requests.last;
    final body = r.data;
    // 无 body 的调用（block/like 等）按空对象返回；有 body 必须是 JSON 对象。
    if (body == null) {
      return (method: r.method, path: r.path, body: const <String, dynamic>{});
    }
    assert(body is Map<String, dynamic>, 'body 必须是 JSON 对象：${r.raw}');
    return (method: r.method, path: r.path, body: body as Map<String, dynamic>);
  }

  setUp(requests.clear);

  // ---------- 断言助手（镜像服务端 DTO 硬约束） ----------

  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  void expectUuid(Object? v, String field) {
    expect(
      v is String && uuidV4.hasMatch(v),
      isTrue,
      reason: '$field 必须是 UUIDv4（服务端 @IsUUID(\'4\')），实际：$v',
    );
  }

  void expectIso8601(Object? v, String field) {
    expect(
      v is String && DateTime.tryParse(v) != null,
      isTrue,
      reason: '$field 必须是 ISO8601，实际：$v',
    );
  }

  final hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  Map<String, dynamic> opOf(Map<String, dynamic> body, int i) {
    final ops = body['ops']! as List<dynamic>;
    expect(ops.length, lessThanOrEqualTo(100), reason: '单批 ≤100（ArrayMaxSize）');
    return ops[i] as Map<String, dynamic>;
  }

  void expectOpEnvelope(Map<String, dynamic> op) {
    expectUuid(op['clientRequestId'], 'op.clientRequestId');
    expect(
      op['entity'],
      isIn(<String>['foodEntry', 'waterLog', 'exerciseLog']),
    );
    expect(op['op'], isIn(<String>['create', 'update', 'delete']));
  }

  // ---------- fasting ----------

  test('PUT /fasting-plans/current：clientRequestId 必带（历史全断根因防线）', () async {
    await FastingPlanApi(buildDio()).putCurrent(FastingPlan.plan16x8);
    final r = lastReq();
    expect(r.method, 'PUT');
    expect(r.path, '/fasting-plans/current');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['planType'], isIn(<String>['14:10', '16:8', '18:6']));
    final window = r.body['eatingWindow']! as Map<String, dynamic>;
    expect(window['start'], matches(hhmm));
    expect(window['end'], matches(hhmm));
    // 窗口时长与 planType 一致（服务端跨字段校验 400）。
    int mins(String t) =>
        int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3));
    final dur =
        (mins(window['end']! as String) -
            mins(window['start']! as String) +
            1440) %
        1440;
    expect(dur, 8 * 60, reason: '16:8 进食窗口必须 8h');
  });

  test('POST /fasting/end：幂等键 + endedAt + B2 窗口签名', () async {
    await FastingReportApi(buildDio()).reportEnd(
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      recordId: 'rec-1',
      endedAtUtc: DateTime.utc(2026, 9, 29, 4),
      plannedStartUtc: DateTime.utc(2026, 9, 28, 12),
      plannedEndUtc: DateTime.utc(2026, 9, 29, 4),
    );
    final r = lastReq();
    expect(r.path, '/fasting/end');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['recordId'], 'rec-1');
    expectIso8601(r.body['endedAt'], 'endedAt');
    expectIso8601(r.body['plannedStartAt'], 'plannedStartAt');
    expectIso8601(r.body['plannedEndAt'], 'plannedEndAt');
  });

  test('POST /fasting/extend：步进 30、累计 ≤240', () async {
    await FastingPlanApi(buildDio()).extendFast(
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      recordId: 'rec-1',
      extendMinutes: 30,
    );
    final r = lastReq();
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    final mins = r.body['extendMinutes']! as int;
    expect(mins % 30, 0);
    expect(mins, inInclusiveRange(30, 240));
  });

  // ---------- streak / users / auth ----------

  test('POST /streak/makeup：幂等键 + 归属日格式', () async {
    responder = (path, data) => <String, dynamic>{
      'currentStreak': 1,
      'longestStreak': 1,
      'lastQualifiedDate': null,
      'makeupCards': <String, dynamic>{
        'stock': 1,
        'grantsThisMonth': 2,
        'expiresAt': '2026-09-30',
        'usableWindowDays': 7,
        'status': 'available',
      },
    };
    addTearDown(() => responder = null);
    await StreakApi(buildDio()).useMendCard(
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      date: '2026-09-28',
    );
    final r = lastReq();
    expect(r.path, '/streak/makeup');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test(
    'PATCH /users/me：字段级 LWW 透传（settingsPrefs/onboardingStatus 在册）',
    () async {
      responder = (path, data) => <String, dynamic>{
        'user': <String, dynamic>{},
      };
      addTearDown(() => responder = null);
      final patch = <String, Object?>{
        'settingsPrefs': <String, Object?>{'locale': 'zh-CN', 'syncedAt': 'x'},
        'onboardingStatus': 'completed',
        'heightCm': 170,
      };
      await UserApi(buildDio()).patchMe(patch);
      final r = lastReq();
      expect(r.method, 'PATCH');
      expect(r.path, '/users/me');
      expect(r.body, patch);
      // 防漂移清单：客户端在用的字段必须全部落在服务端 PatchUserDto 白名单。
      const serverPatchable = <String>{
        'nickname',
        'gender',
        'birthYear',
        'heightCm',
        'weightKg',
        'activityLevel',
        'goal',
        'targetWeightKg',
        'targetDate',
        'timezone',
        'locale',
        'themePref',
        'accessibilityPrefs',
        'settingsPrefs',
        'onboardingStatus',
      };
      for (final key in r.body.keys) {
        expect(
          serverPatchable,
          contains(key),
          reason: '服务端 PatchUserDto 无字段 $key（whitelist 会被剥离或 400）',
        );
      }
    },
  );

  test('auth：register/login/changePassword 字段与用户名策略', () async {
    responder = (path, data) => <String, dynamic>{
      'accessToken': 'a',
      'refreshToken': 'r',
      'expiresIn': 7200,
      'user': <String, dynamic>{'id': 'u1'},
    };
    addTearDown(() => responder = null);
    final api = AuthApi(buildDio());
    await api.register(
      username: 'wcg_01',
      password: 'pass1234',
      deviceId: 'd1',
    );
    var r = lastReq();
    expect(r.path, '/auth/register');
    expect(r.body['username'], matches(RegExp(r'^[a-zA-Z0-9_]{3,20}$')));
    expect((r.body['password']! as String).length, inInclusiveRange(8, 64));
    final device = r.body['device']! as Map<String, dynamic>;
    expect(device['deviceId'], isNotEmpty);
    expect(device['platform'], isIn(<String>['ios', 'android']));

    await api.login(username: 'wcg_01', password: 'pass1234');
    r = lastReq();
    expect(r.path, '/auth/login');
    expect(r.body['username'], isNotEmpty);
    expect(r.body['password'], isNotEmpty);

    await api.changePassword(oldPassword: 'pass1234', newPassword: 'pass5678');
    r = lastReq();
    expect(r.path, '/auth/password/change');
    expect((r.body['newPassword']! as String).length, inInclusiveRange(8, 64));
  });

  // ---------- social / moderation ----------

  test('POST /posts：text 1-500、imageUrls ≤9、avatarId 0-63、幂等键', () async {
    responder = (path, data) => <String, dynamic>{};
    addTearDown(() => responder = null);
    await SocialApi(buildDio()).createPost(
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      text: 'day 3 done',
      imageUrls: List<String>.generate(3, (i) => '/v1/uploads/$i.jpg'),
      anonymous: true,
      avatarId: 7,
    );
    final r = lastReq();
    expect(r.path, '/posts');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    final text = r.body['text']! as String;
    expect(text.length, inInclusiveRange(1, 500));
    expect(
      (r.body['imageUrls']! as List<dynamic>).length,
      lessThanOrEqualTo(9),
    );
    expect(r.body['anonymous'], isTrue);
    expect(r.body['avatarId'], inInclusiveRange(0, 63));
  });

  test('POST /posts/:id/report：reason ≤200；block/unblock 无 body', () async {
    final api = SocialApi(buildDio());
    await api.report('p1', reason: 'spam');
    var r = lastReq();
    expect(r.path, '/posts/p1/report');
    expect((r.body['reason']! as String).length, lessThanOrEqualTo(200));

    await api.blockUser('u2');
    r = lastReq();
    expect(r.method, 'POST');
    expect(r.path, '/users/u2/block');
    await api.unblockUser('u2');
    expect(requests.last.method, 'DELETE');
  });

  test('moderation review：action 枚举 + reason ≤200', () async {
    final api = RemoteModerationApi(dio: buildDio());
    await api.review('c1', action: 'reject', reason: '数值存疑');
    final r = lastReq();
    expect(r.path, '/moderation/food-candidates/c1/review');
    expect(r.body['action'], isIn(<String>['approve', 'reject']));
    expect((r.body['reason']! as String).length, lessThanOrEqualTo(200));
  });

  // ---------- foods ----------

  CustomFoodDraft draft() => CustomFoodDraft(
    nameZh: '自制酸奶',
    aliasesZh: const <String>['酸奶'],
    per100g: const NutritionSnapshot(kcal: 60, proteinG: 3, carbG: 4, fatG: 3),
    source: CustomFoodSource.manual,
  );

  test('POST /foods/custom：幂等键 + per100g 区间 + source 枚举', () async {
    responder = (path, data) => <String, dynamic>{'id': 'cf_1'};
    addTearDown(() => responder = null);
    await RemoteCustomFoodApi(dio: buildDio()).createCustom(
      draft(),
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
    );
    final r = lastReq();
    expect(r.path, '/foods/custom');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect((r.body['nameZh']! as String).length, inInclusiveRange(1, 50));
    expect(
      (r.body['aliasesZh']! as List<dynamic>).length,
      lessThanOrEqualTo(20),
    );
    final p = r.body['per100g']! as Map<String, dynamic>;
    expect(p['kcal'], inInclusiveRange(0, 900));
    expect(p['proteinG'], inInclusiveRange(0, 100));
    expect(p['carbG'], inInclusiveRange(0, 100));
    expect(p['fatG'], inInclusiveRange(0, 100));
    expect(r.body['source'], isIn(<String>['manual', 'llm-estimate']));
  });

  test('POST /foods/custom/:id/contribute：barcode 与佐证图成对、条码 8-14 位', () async {
    responder = (path, data) => <String, dynamic>{'status': 'pending'};
    addTearDown(() => responder = null);
    final api = RemoteCustomFoodApi(dio: buildDio());
    await api.contribute(
      'cf_1',
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/evi.jpg',
    );
    var r = lastReq();
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['barcode'], matches(RegExp(r'^\d{8,14}$')));
    expect(
      r.body['evidenceImageUrl'],
      matches(RegExp(r'^(https?:\/\/|\/\/|\/)[^\s]*$')),
    );

    // 不成对调用方（只传 barcode）：客户端防御性整体省略（服务端成对契约）。
    await api.contribute(
      'cf_1',
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
      barcode: '6901234567892',
    );
    r = lastReq();
    expect(r.body.containsKey('barcode'), isFalse);
    expect(r.body.containsKey('evidenceImageUrl'), isFalse);
  });

  test('PATCH /foods/custom/:id 与 POST /foods/:id/correction 契约', () async {
    responder = (path, data) => <String, dynamic>{'status': 'pending'};
    addTearDown(() => responder = null);
    final api = RemoteCustomFoodApi(dio: buildDio());
    await api.updateCustom('cf_1', draft());
    var r = lastReq();
    expect(r.method, 'PATCH');
    expect(r.body.containsKey('clientRequestId'), isFalse, reason: '更新不做幂等键');
    expect(r.body['source'], isIn(<String>['manual', 'llm-estimate']));

    await api.submitCorrection(
      'f1',
      draft(),
      clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
    );
    r = lastReq();
    expect(r.path, '/foods/f1/correction');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['per100g'], isNotNull);
  });

  // ---------- /sync push（foodEntry/waterLog/exerciseLog） ----------

  Object? syncResponder(String path, Object? data) {
    final ops = (data! as Map<String, dynamic>)['ops']! as List<dynamic>;
    return <String, dynamic>{
      'results': <Map<String, dynamic>>[
        for (final op in ops.cast<Map<String, dynamic>>())
          <String, dynamic>{
            'clientRequestId': op['clientRequestId'],
            'status': 'applied',
            'serverEntry': <String, dynamic>{
              'id': 'srv-1',
              'version': 1,
              'updatedAt': '2026-09-29T00:00:00.000Z',
            },
          },
      ],
    };
  }

  FoodEntry entry({bool deleted = false, bool synced = false}) => FoodEntry(
    localId: 'l1',
    userId: 'u1',
    serverId: synced ? 'srv-1' : null,
    clientRequestId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
    syncStatus: SyncStatus.pending,
    localVersion: 1,
    serverVersion: synced ? 3 : null,
    retryCount: 0,
    deleted: deleted,
    datetimeUtc: '2026-09-29T01:00:00.000Z',
    localDate: '2026-09-29',
    foodId: 'f1',
    amountG: 150,
    kcal: 200,
    proteinG: 10,
    carbG: 20,
    fatG: 5,
    source: EntrySource.manual,
    duringFast: false,
    createdAtUtc: '2026-09-29T01:00:00.000Z',
    updatedAtUtc: '2026-09-29T01:00:00.000Z',
  );

  test(
    '/sync/push foodEntry：create 无 serverId / update 带 baseVersion / delete op',
    () async {
      responder = syncResponder;
      addTearDown(() => responder = null);
      final sync = RemoteRecordSync(
        dio: buildDio(),
        location: tz.getLocation('Asia/Shanghai'),
      );
      await sync.pushBatch(<FoodEntry>[
        entry(),
        entry(synced: true),
        entry(synced: true, deleted: true),
      ]);
      final r = lastReq();
      expect(r.path, '/sync/push');

      final create = opOf(r.body, 0);
      expectOpEnvelope(create);
      expect(create['op'], 'create');
      expect(create.containsKey('serverId'), isFalse);
      final payload = create['payload']! as Map<String, dynamic>;
      expectIso8601(payload['eatenAt'], 'payload.eatenAt');
      expect(payload['foodId'], 'f1');
      expect(payload['grams'], inInclusiveRange(0.1, 5000));
      expect(
        payload['inputMethod'],
        isIn(<String>['photo', 'voice', 'frequent', 'manual', 'barcode']),
      );

      final update = opOf(r.body, 1);
      expectOpEnvelope(update);
      expect(update['op'], 'update');
      expect(update['serverId'], 'srv-1');
      expect(update['baseVersion'], 3);

      final delete = opOf(r.body, 2);
      expectOpEnvelope(delete);
      expect(delete['op'], 'delete');
      expect(delete['serverId'], 'srv-1');
    },
  );

  test(
    '/sync/push waterLog：create（amountMl 1-5000）与 tombstone delete',
    () async {
      responder = syncResponder;
      addTearDown(() => responder = null);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      const cid1 = '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f';
      const cid2 = '4f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f';
      await db.waterLogDao.insertLog(
        WaterLogsCompanion(
          localId: const Value('w1'),
          userId: const Value('u1'),
          amountMl: const Value(300),
          datetimeUtc: const Value('2026-09-29T01:00:00.000Z'),
          localDate: const Value('2026-09-29'),
          clientRequestId: const Value(cid1),
          createdAtUtc: const Value('2026-09-29T01:00:00.000Z'),
        ),
      );
      await db.waterLogDao.insertLog(
        WaterLogsCompanion(
          localId: const Value('w2'),
          userId: const Value('u1'),
          amountMl: const Value(200),
          datetimeUtc: const Value('2026-09-29T02:00:00.000Z'),
          localDate: const Value('2026-09-29'),
          clientRequestId: const Value(cid2),
          serverId: const Value('srv-w2'),
          deleted: const Value(true),
          createdAtUtc: const Value('2026-09-29T02:00:00.000Z'),
        ),
      );
      await RemoteWaterLogSync(dio: buildDio()).pushPending(db, 'u1');
      final r = lastReq();
      expect(r.body['ops'], hasLength(2));

      final create = opOf(r.body, 0);
      expectOpEnvelope(create);
      expect(create['entity'], 'waterLog');
      final payload = create['payload']! as Map<String, dynamic>;
      expect(payload['amountMl'], inInclusiveRange(1, 5000));
      expectIso8601(payload['loggedAt'], 'payload.loggedAt');
      expect(payload['localDate'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

      final delete = opOf(r.body, 1);
      expectOpEnvelope(delete);
      expect(delete['op'], 'delete');
      expect(delete['serverId'], 'srv-w2');
      expectUuid(
        (delete['payload']! as Map<String, dynamic>)['clientRequestId'],
        'delete payload 兜底定位键',
      );
    },
  );

  test(
    '/sync/push exerciseLog：create（typeKey/durationMin/kcal/steps/source 边界）',
    () async {
      responder = syncResponder;
      addTearDown(() => responder = null);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.exerciseLogDao.insertLog(
        ExerciseLogsCompanion(
          localId: const Value('e1'),
          userId: const Value('u1'),
          typeKey: const Value('walk'),
          durationMin: const Value(30),
          kcal: const Value(120.5),
          steps: const Value(3000),
          localDate: const Value('2026-09-29'),
          clientRequestId: const Value('3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f'),
          createdAtUtc: const Value('2026-09-29T01:00:00.000Z'),
        ),
      );
      await RemoteExerciseLogSync(dio: buildDio()).pushPending(db, 'u1');
      final op = opOf(lastReq().body, 0);
      expectOpEnvelope(op);
      expect(op['entity'], 'exerciseLog');
      final payload = op['payload']! as Map<String, dynamic>;
      expect(payload['typeKey'], isA<String>());
      expect(payload['durationMin'], inInclusiveRange(0, 1440));
      expect(payload['kcal'], inInclusiveRange(0.1, 10000));
      expect(payload['steps'], inInclusiveRange(1, 200000));
      if (payload.containsKey('source')) {
        expect(
          payload['source'],
          'screenshot',
          reason: 'source 枚举只有 screenshot',
        );
      }
    },
  );

  // ---------- weight-logs / analytics / uploads ----------

  test('POST /weight-logs：幂等键 + date 格式 + 区间（20-300kg / 1-70%）', () async {
    final store = WeightLogStore.inMemory(userId: 'u1');
    await store.save('2026-09-29', 70.5, bodyFatPct: 22);
    await RemoteWeightLogSync(dio: buildDio()).pushPending(store);
    final r = lastReq();
    expect(r.path, '/weight-logs');
    expectUuid(r.body['clientRequestId'], 'clientRequestId');
    expect(r.body['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(r.body['weightKg'], inInclusiveRange(20, 300));
    expect(r.body['bodyFatPct'], inInclusiveRange(1, 70));
  });

  test(
    'POST /analytics/events：{data:{events[]}, meta:{requestId,clientTime}} 信封',
    () async {
      await RemoteAnalyticsClient(dio: buildDio()).send(<AnalyticsEvent>[
        AnalyticsEvent(
          eventId: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
          name: 'record_flow_success',
          timestamp: 1790000000000,
          clientDate: '2026-09-29',
          common: const <String, Object?>{'anon_id': 'x'},
          properties: const <String, Object?>{'record_kind': 'water'},
        ),
      ]);
      final r = lastReq();
      expect(r.path, '/analytics/events');
      final data = r.body['data']! as Map<String, dynamic>;
      final events = data['events']! as List<dynamic>;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['event_id'], isNotEmpty);
      expect(event['event_name'], matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      final meta = r.body['meta']! as Map<String, dynamic>;
      expect(meta['requestId'], isNotEmpty);
      expectIso8601(meta['clientTime'], 'meta.clientTime');
    },
  );

  test('POST /uploads：multipart 字段名固定 file（服务端 FileInterceptor 契约）', () async {
    responder = (path, data) => <String, dynamic>{
      'url': '/v1/uploads/x.jpg',
      'bytes': 4,
      'mime': 'image/jpeg',
    };
    addTearDown(() => responder = null);
    // 最小 JPEG 魔数头（detectImageFormat 嗅探）
    await UploadApi(
      buildDio(),
    ).uploadImage(Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF, 0xE0]));
    final r = requests.last;
    expect(r.path, '/uploads');
    expect(r.raw, contains('name="file"'), reason: 'multipart 字段名必须是 file');
  });
}

/// 录制真实序列化产物的 Dio 适配器（JSON 解码 + 原始文本双留档）。
final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.requests, this.responder);

  final List<({String method, String path, Object? data, String raw})> requests;
  final Object? Function(String path, Object? data) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final buffer = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        buffer.addAll(chunk);
      }
    }
    final raw = utf8.decode(buffer, allowMalformed: true);
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      decoded = null; // multipart 等非 JSON 载荷
    }
    requests.add((
      method: options.method,
      path: options.path,
      data: decoded,
      raw: raw,
    ));
    final body = responder(options.path, decoded);
    return ResponseBody.fromString(
      jsonEncode(body ?? const <String, dynamic>{}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

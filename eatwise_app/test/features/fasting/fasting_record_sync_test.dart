import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/fasting/data/remote_fasting_record_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_result_mapping.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';

/// 断食记录两态同步（2026-09-29 拍板 fastingRecord 全量进 /sync）：
/// 本地关闭周期 pending → /sync/push entity=fastingRecord 上行回填；
/// /sync/pull fastingRecordChanges 下行（换机全量恢复；本机为准不覆盖，
/// 仅收敛同步标记）；tombstone 双向；引擎挂接（仅登录态）。
void main() {
  late FakeHttpAdapter adapter;
  late RemoteFastingRecordSync fastingSync;
  late RemoteRecordSync recordSync;
  late AppDatabase db;

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    fastingSync = RemoteFastingRecordSync(dio: dio);
    recordSync = RemoteRecordSync(dio: dio, location: tz.UTC);
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  /// 落一条本地关闭周期（pending 待上行）。
  Future<FastingRecord> seedLocal({
    String userId = 'u-1',
    String date = '2026-08-01',
    int startUtc = 1785585600, // 2026-08-01T12:00:00Z
    int plannedSec = 16 * 3600,
    int actualSec = 16 * 3600,
    int extendedMinutes = 0,
    CycleResult result = CycleResult.completedOnTime,
    bool qualified = true,
    SyncStatus status = SyncStatus.pending,
    String? serverId,
    bool deleted = false,
  }) async {
    final companion = FastingRecordsCompanion(
      localId: Value('$userId-$date'),
      userId: Value(userId),
      attributionDate: Value(date),
      startUtc: Value(startUtc),
      endUtc: Value(startUtc + actualSec),
      actualSec: Value(actualSec),
      plannedSec: Value(plannedSec),
      extendedMinutes: Value(extendedMinutes),
      result: Value(result.name),
      qualified: Value(qualified),
      clientRequestId: Value('cr-$date'),
      syncStatus: Value(status),
      serverId: Value(serverId),
      deleted: Value(deleted),
      createdAtUtc: const Value('2026-08-01T12:00:00.000Z'),
    );
    await db.fastingRecordDao.upsertRecord(companion);
    return (await db.fastingRecordDao.getByLocalId('$userId-$date'))!;
  }

  void stubPush(List<Map<String, dynamic>> results) {
    adapter.stub(
      '/sync/push',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'results': results,
          'syncToken': 'st_x',
        }),
      ),
    );
  }

  void stubPull(Map<String, dynamic> body) {
    adapter.stub(
      '/sync/pull',
      StubResponse.json(200, StubResponse.envelope(body)),
    );
  }

  Map<String, dynamic> pushOp(int requestIndex, int opIndex) {
    final body = adapter.requestBodies[requestIndex] as Map<dynamic, dynamic>;
    return ((body['ops']! as List<dynamic>)[opIndex]) as Map<String, dynamic>;
  }

  group('上行 pushPending（/sync/push entity=fastingRecord）', () {
    test(
      'create applied → 回填 serverId 转 synced；op 载荷完整（锚点 ISO + result 映射）',
      () async {
        final row = await seedLocal(
          result: CycleResult.completedExtended,
          extendedMinutes: 30,
        );
        stubPush(<Map<String, dynamic>>[
          <String, dynamic>{
            'clientRequestId': row.clientRequestId,
            'status': 'applied',
            'serverEntry': <String, dynamic>{'id': 'srv-f1', 'version': 1},
          },
        ]);

        await fastingSync.pushPending(db, 'u-1');

        final stored = (await db.fastingRecordDao.getByLocalId(row.localId))!;
        expect(stored.syncStatus, SyncStatus.synced);
        expect(stored.serverId, 'srv-f1');
        expect(await db.fastingRecordDao.pendingForUser('u-1'), isEmpty);

        final op = pushOp(0, 0);
        expect(op['entity'], 'fastingRecord');
        expect(op['op'], 'create');
        expect(op['clientRequestId'], 'cr-2026-08-01');
        final payload = op['payload']! as Map<dynamic, dynamic>;
        expect(payload['attributionDate'], '2026-08-01');
        expect(payload['plannedStartAt'], '2026-08-01T12:00:00.000Z');
        expect(payload['plannedEndAt'], '2026-08-02T04:00:00.000Z');
        expect(payload['actualStartAt'], '2026-08-01T12:00:00.000Z');
        expect(payload['actualEndAt'], '2026-08-02T04:00:00.000Z');
        expect(payload['extendedMinutes'], 30);
        expect(payload['fastedMinutes'], 16 * 60);
        expect(payload['result'], 'completed');
        expect(payload['isQualified'], isTrue);
        // 同日 LWW 仲裁依据（服务端比较既有记录 updatedAt）。
        expect(payload['updatedAtUtc'], '2026-08-01T12:00:00.000Z');
      },
    );

    test(
      'result 映射：brokenEarly→broken / completedEarlyPass→ended_early',
      () async {
        await seedLocal(
          date: '2026-08-02',
          result: CycleResult.brokenEarly,
          qualified: false,
        );
        await seedLocal(
          date: '2026-08-03',
          result: CycleResult.completedEarlyPass,
        );
        stubPush(<Map<String, dynamic>>[
          <String, dynamic>{
            'clientRequestId': 'cr-2026-08-02',
            'status': 'applied',
            'serverEntry': <String, dynamic>{'id': 'srv-f2', 'version': 1},
          },
          <String, dynamic>{
            'clientRequestId': 'cr-2026-08-03',
            'status': 'applied',
            'serverEntry': <String, dynamic>{'id': 'srv-f3', 'version': 1},
          },
        ]);

        await fastingSync.pushPending(db, 'u-1');

        expect(
          (pushOp(0, 0)['payload']! as Map<dynamic, dynamic>)['result'],
          'broken',
        );
        expect(
          (pushOp(0, 1)['payload']! as Map<dynamic, dynamic>)['result'],
          'ended_early',
        );
        expect(
          (pushOp(0, 0)['payload']! as Map<dynamic, dynamic>)['isQualified'],
          isFalse,
        );
      },
    );

    test('网络错误：整批保持 pending，离线状态翻转', () async {
      await seedLocal();
      adapter.stub('/sync/push', StubResponse.networkError('boom'));

      await fastingSync.pushPending(db, 'u-1');

      expect(await db.fastingRecordDao.pendingForUser('u-1'), hasLength(1));
      expect(fastingSync.isOnline, isFalse);
    });

    test('VALIDATION_ERROR 永久拒绝：保持 pending 不静默删历史（与饮水/运动不同口径）', () async {
      final row = await seedLocal();
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': row.clientRequestId,
          'status': 'error',
          'error': <String, dynamic>{'code': 'VALIDATION_ERROR'},
        },
      ]);

      await fastingSync.pushPending(db, 'u-1');

      final stored = (await db.fastingRecordDao.getByLocalId(row.localId))!;
      expect(stored.syncStatus, SyncStatus.pending); // 历史行保留，下轮重试
    });

    test('tombstone 上行 delete applied / NOT_FOUND → 本地物理清除', () async {
      final row = await seedLocal(
        status: SyncStatus.pending,
        serverId: 'srv-f9',
        deleted: true,
      );
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': row.clientRequestId,
          'status': 'applied',
        },
      ]);

      await fastingSync.pushPending(db, 'u-1');

      expect(await db.fastingRecordDao.getByLocalId(row.localId), isNull);
      final op = pushOp(0, 0);
      expect(op['op'], 'delete');
      expect(op['serverId'], 'srv-f9');
      expect(
        (op['payload']! as Map<dynamic, dynamic>)['clientRequestId'],
        row.clientRequestId,
      );
    });
  });

  group('下行 fastingRecordChanges（/sync/pull 随行）', () {
    test('本地缺失 → 落 synced 新行（换机全量恢复）；on_track 跳过；tombstone 清除', () async {
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'fastingRecordChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'fastingRecord',
            'id': 'srv-f1',
            'clientRequestId': null,
            'attributionDate': '2026-06-15', // >14 天历史（轻量回填补不到的存量）
            'plannedStartAt': '2026-06-14T12:00:00.000Z',
            'plannedEndAt': '2026-06-15T04:00:00.000Z',
            'actualStartAt': '2026-06-14T12:00:00.000Z',
            'actualEndAt': '2026-06-15T04:00:00.000Z',
            'extendedMinutes': 0,
            'fastedMinutes': 16 * 60,
            'result': 'completed',
            'isQualified': true,
            'version': 1,
          },
          <String, dynamic>{
            'entity': 'fastingRecord',
            'id': 'srv-ongoing',
            'attributionDate': '2026-08-01',
            'plannedStartAt': '2026-07-31T12:00:00.000Z',
            'plannedEndAt': '2026-08-01T04:00:00.000Z',
            'result': 'on_track',
            'isQualified': false,
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'u-1', null);

      final rows = await db.fastingRecordDao.recordsOf('u-1');
      expect(rows, hasLength(1)); // on_track 无结束锚点跳过
      final stored = rows.single;
      expect(stored.localId, 'u-1-2026-06-15');
      expect(stored.serverId, 'srv-f1');
      expect(stored.syncStatus, SyncStatus.synced);
      expect(stored.qualified, isTrue);
      expect(stored.result, CycleResult.completedOnTime.name);
      expect(stored.actualSec, 16 * 3600);
      expect(
        stored.clientRequestId,
        'server-srv-f1',
      ); // 服务端 clientRequestId 缺省兜底

      // tombstone 下行 → 清除已同步行。
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'fastingRecordChanges': <dynamic>[
          <String, dynamic>{
            'tombstone': <String, dynamic>{
              'entity': 'fastingRecord',
              'id': 'srv-f1',
              'deletedAt': '2026-08-02T00:00:00.000Z',
            },
          },
        ],
        'syncToken': 'st_2',
        'hasMore': false,
      });
      await recordSync.pullDown(db, 'u-1', 'st_1');
      expect(await db.fastingRecordDao.recordsOf('u-1'), isEmpty);
    });

    test('本地 pending 同日：markSynced 收敛 + 回填 serverId，内容本机为准不覆盖', () async {
      // 本机 2026-08-01 周期 broken 落库（F2 未上行成功 → pending）；
      // 服务端同日已有终态 completed（ghost 自动结算口径分叉）。
      final local = await seedLocal(
        result: CycleResult.brokenEarly,
        qualified: false,
        actualSec: 10 * 3600,
      );
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'fastingRecordChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'fastingRecord',
            'id': 'srv-f1',
            'attributionDate': '2026-08-01',
            'plannedStartAt': '2026-07-31T12:00:00.000Z',
            'plannedEndAt': '2026-08-01T04:00:00.000Z',
            'actualStartAt': '2026-07-31T12:00:00.000Z',
            'actualEndAt': '2026-08-01T04:00:00.000Z',
            'extendedMinutes': 0,
            'fastedMinutes': 16 * 60,
            'result': 'completed',
            'isQualified': true,
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'u-1', null);

      final stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.syncStatus, SyncStatus.synced); // 标记收敛
      expect(stored.serverId, 'srv-f1');
      expect(stored.result, CycleResult.brokenEarly.name); // 内容本机为准
      expect(stored.qualified, isFalse);
      expect(stored.actualSec, 10 * 3600);
    });

    test('本地 synced 无 serverId（老版本 F2 上行行）→ 仅回填 serverId', () async {
      final local = await seedLocal(status: SyncStatus.synced);
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'fastingRecordChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'fastingRecord',
            'id': 'srv-f1',
            'attributionDate': '2026-08-01',
            'plannedStartAt': '2026-07-31T12:00:00.000Z',
            'plannedEndAt': '2026-08-01T04:00:00.000Z',
            'actualStartAt': '2026-07-31T12:00:00.000Z',
            'actualEndAt': '2026-08-01T04:00:00.000Z',
            'extendedMinutes': 0,
            'result': 'completed',
            'isQualified': true,
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'u-1', null);

      final stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.serverId, 'srv-f1');
      expect(stored.syncStatus, SyncStatus.synced);
    });
  });

  group('同日双端分叉 LWW（2026-09-29 拍板确定性收敛）', () {
    Map<String, dynamic> serverChange({
      required String updatedAt,
      String result = 'completed',
      bool isQualified = true,
      int fastedMinutes = 16 * 60,
    }) {
      return <String, dynamic>{
        'entity': 'fastingRecord',
        'id': 'srv-f1',
        'attributionDate': '2026-08-01',
        'plannedStartAt': '2026-07-31T12:00:00.000Z',
        'plannedEndAt': '2026-08-01T04:00:00.000Z',
        'actualStartAt': '2026-07-31T12:00:00.000Z',
        'actualEndAt': '2026-08-01T04:00:00.000Z',
        'extendedMinutes': 0,
        'fastedMinutes': fastedMinutes,
        'result': result,
        'isQualified': isQualified,
        'version': 2,
        'updatedAt': updatedAt,
      };
    }

    void stubPullWith(Map<String, dynamic> change) {
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'fastingRecordChanges': <dynamic>[change],
        'syncToken': 'st_1',
        'hasMore': false,
      });
    }

    test('服务端记录更新（终态）→ 覆盖本地内容并收敛 synced；重复下行幂等不再写', () async {
      // 本机同日 broken（createdAtUtc=2026-08-01T12:00Z）；服务端 09-01
      // 更新的终态 completed（updatedAt 更晚）→ 服务端胜。
      final local = await seedLocal(
        result: CycleResult.brokenEarly,
        qualified: false,
        actualSec: 10 * 3600,
      );
      stubPullWith(serverChange(updatedAt: '2026-09-01T00:00:00.000Z'));

      await recordSync.pullDown(db, 'u-1', null);

      var stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.result, CycleResult.completedOnTime.name); // 内容被覆盖
      expect(stored.qualified, isTrue);
      expect(stored.actualSec, 16 * 3600);
      expect(stored.syncStatus, SyncStatus.synced);
      expect(stored.serverId, 'srv-f1');
      // 幂等稳定锚点：createdAtUtc 记为服务端 updatedAt。
      expect(stored.createdAtUtc, '2026-09-01T00:00:00.000Z');

      // 重复下行同一视图：updatedAt 不再更晚 → 不再重写（行内容不变）。
      stubPullWith(serverChange(updatedAt: '2026-09-01T00:00:00.000Z'));
      await recordSync.pullDown(db, 'u-1', 'st_1');
      stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.createdAtUtc, '2026-09-01T00:00:00.000Z');
      expect(stored.result, CycleResult.completedOnTime.name);
    });

    test('本机更新（createdAtUtc 更晚）→ 内容本机为准，pending 保持待上行', () async {
      final local = await seedLocal(
        result: CycleResult.brokenEarly,
        qualified: false,
        actualSec: 10 * 3600,
      );
      // 服务端 updatedAt 早于本机写入 → 本机胜，内容不动、pending 保持
      // （下轮上行由服务端 LWW 反向覆盖）。
      stubPullWith(serverChange(updatedAt: '2020-01-01T00:00:00.000Z'));

      await recordSync.pullDown(db, 'u-1', null);

      final stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.result, CycleResult.brokenEarly.name);
      expect(stored.qualified, isFalse);
      expect(stored.actualSec, 10 * 3600);
      expect(stored.syncStatus, SyncStatus.pending);
    });

    test('服务端为 on_track（进行中）→ 不覆盖本地内容，仅收敛同步标记', () async {
      final local = await seedLocal(
        result: CycleResult.brokenEarly,
        qualified: false,
      );
      stubPullWith(<String, dynamic>{
        'entity': 'fastingRecord',
        'id': 'srv-f1',
        'attributionDate': '2026-08-01',
        'plannedStartAt': '2026-07-31T12:00:00.000Z',
        'plannedEndAt': '2026-08-01T04:00:00.000Z',
        'result': 'on_track',
        'isQualified': false,
        'version': 1,
        'updatedAt': '2999-09-01T00:00:00.000Z', // 即便更新也不覆盖进行中
      });

      await recordSync.pullDown(db, 'u-1', null);

      final stored = (await db.fastingRecordDao.getByLocalId(local.localId))!;
      expect(stored.result, CycleResult.brokenEarly.name); // 内容不动
      expect(stored.syncStatus, SyncStatus.synced); // 标记收敛
      expect(stored.serverId, 'srv-f1');
    });
  });

  group('引擎挂接（RecordSyncEngine.syncNow）', () {
    test('登录态触发 fastingRecord 上行（pending 行本轮转 synced）；匿名态跳过', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await seedLocal(); // u-1 pending
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': 'cr-2026-08-01',
          'status': 'applied',
          'serverEntry': <String, dynamic>{'id': 'srv-f1', 'version': 1},
        },
      ]);

      final repoU1 = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
        userId: 'u-1',
      );
      final engineU1 = RecordSyncEngine(
        repository: repoU1,
        prefs: prefs,
        fastingRecordSync: fastingSync,
      );
      await engineU1.syncNow();
      // 引擎本轮把 pending 断食行推上去（唯一 HTTP 请求 = /sync/push）。
      expect(adapter.requestBodies, hasLength(1));
      final stored = (await db.fastingRecordDao.getByLocalId(
        'u-1-2026-08-01',
      ))!;
      expect(stored.syncStatus, SyncStatus.synced);
      expect(stored.serverId, 'srv-f1');
      await repoU1.dispose();

      // 匿名态：pending 行保留不上行（无 HTTP 请求）。
      await seedLocal(userId: 'anonymous', date: '2026-08-05');
      final requestCountBefore = adapter.requestBodies.length;
      final repoAnon = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
        userId: 'anonymous',
      );
      final engineAnon = RecordSyncEngine(
        repository: repoAnon,
        prefs: prefs,
        fastingRecordSync: fastingSync,
      );
      await engineAnon.syncNow();
      expect(adapter.requestBodies, hasLength(requestCountBefore));
      final anonRow = (await db.fastingRecordDao.getByLocalId(
        'anonymous-2026-08-05',
      ))!;
      expect(anonRow.syncStatus, SyncStatus.pending);
      await repoAnon.dispose();
    });
  });

  group('结果映射纯函数', () {
    test('本地 ↔ 服务端双向映射', () {
      expect(
        serverResultNameOf(CycleResult.brokenEarly.name, qualified: false),
        'broken',
      );
      expect(
        serverResultNameOf(
          CycleResult.completedEarlyPass.name,
          qualified: true,
        ),
        'ended_early',
      );
      expect(
        serverResultNameOf(CycleResult.completedOnTime.name, qualified: true),
        'completed',
      );
      expect(serverResultNameOf('unknown', qualified: true), 'completed');
      expect(serverResultNameOf('unknown', qualified: false), 'broken');

      expect(
        localResultNameOf('broken', extendedMinutes: 0),
        CycleResult.brokenEarly.name,
      );
      expect(
        localResultNameOf('ended_early', extendedMinutes: 0),
        CycleResult.completedEarlyPass.name,
      );
      expect(
        localResultNameOf('completed', extendedMinutes: 30),
        CycleResult.completedExtended.name,
      );
      expect(
        localResultNameOf('completed', extendedMinutes: 0),
        CycleResult.completedOnTime.name,
      );
      // 2026-09-30：makeup 保留独立身份（补签只计达标、不计断食时长），
      // 不再塌缩为 completedOnTime。
      expect(
        localResultNameOf('makeup', extendedMinutes: 0),
        CycleResult.makeup.name,
      );
      expect(
        serverResultNameOf(CycleResult.makeup.name, qualified: true),
        'makeup',
      );
      expect(isRealFastResult(CycleResult.makeup.name), isFalse);
      expect(isRealFastResult(CycleResult.completedOnTime.name), isTrue);
    });
  });
}

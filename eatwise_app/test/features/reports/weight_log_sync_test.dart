import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/network/fake_http_adapter.dart';

/// 体重记录推拉同步（阶段 C）：pending 上行 POST /weight-logs（幂等 upsert）
/// 回填 synced；GET /weight-logs 下行 LWW 合并；离线保持 pending 下轮重试。
void main() {
  late FakeHttpAdapter adapter;
  late RemoteWeightLogSync sync;
  late WeightLogStore store;

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    sync = RemoteWeightLogSync(dio: dio);
    store = WeightLogStore.inMemory();
  });

  Map<String, dynamic> postBody(int index) =>
      (adapter.requestBodies[index] as Map<dynamic, dynamic>).cast();

  test('上行：pending 逐条 POST（含体脂率与幂等键），成功转 synced', () async {
    await store.save('2026-09-16', 66.0, bodyFatPct: 18.5);
    await store.save('2026-09-17', 65.5);

    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{'id': 'srv-1'}),
      ),
    );
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{'id': 'srv-2'}),
      ),
    );

    await sync.pushPending(store);

    expect(adapter.requestsTo('/weight-logs'), 2);
    // 按日期升序上行；幂等键随条目透传。
    expect(postBody(0)['date'], '2026-09-16');
    expect(postBody(0)['weightKg'], 66.0);
    expect(postBody(0)['bodyFatPct'], 18.5);
    expect(postBody(0)['clientRequestId'], isNotEmpty);
    expect(postBody(1)['date'], '2026-09-17');
    expect(store.pendingEntries(), isEmpty);
  });

  test('上行：断网 → 保持 pending 且判离线（下轮重试）', () async {
    await store.save('2026-09-17', 65.5);
    adapter.stub('/weight-logs', StubResponse.networkError('offline'));

    await sync.pushPending(store);

    expect(store.pendingEntries(), hasLength(1));
    expect(sync.isOnline, isFalse);
  });

  test('上行：同日覆写生成新幂等键，仅最新一条待上行', () async {
    await store.save('2026-09-17', 70.0);
    await store.save('2026-09-17', 69.2); // 同日覆写
    final pending = store.pendingEntries();
    expect(pending, hasLength(1));
    expect(pending.single.value.kg, 69.2);
  });

  test('下行：远端新区间合并为 synced；本地 pending 不被覆盖', () async {
    await store.save('2026-09-17', 65.5); // 本地 pending
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'logs': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-09-16',
              'weightKg': 66.4,
              'bodyFatPct': null,
              'updatedAt': '2026-09-16T01:00:00.000Z',
            },
            <String, dynamic>{
              'date': '2026-09-17',
              'weightKg': 99.9, // 同日远端旧值：本地 pending 优先，不覆盖
              'bodyFatPct': null,
              'updatedAt': '2026-09-17T00:30:00.000Z',
            },
          ],
        }),
      ),
    );

    await sync.pullDown(store);

    final entries = store.loadEntries('2026-09-16', '2026-09-17');
    expect(entries['2026-09-16']?.kg, 66.4);
    expect(entries['2026-09-16']?.synced, isTrue);
    expect(entries['2026-09-17']?.kg, 65.5); // 本地 pending 保持
    expect(store.pendingEntries(), hasLength(1));
  });

  test('下行：远端较新覆盖本地已同步条目（LWW）', () async {
    await store.save('2026-09-17', 65.5);
    await store.markSynced(
      '2026-09-17',
      store.pendingEntries().single.value.clientRequestId,
    );
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'logs': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-09-17',
              'weightKg': 64.8,
              'bodyFatPct': 17.9,
              'updatedAt': '2999-09-17T02:00:00.000Z', // 远端更新
            },
          ],
        }),
      ),
    );

    await sync.pullDown(store);

    final entry = store.loadEntries('2026-09-17', '2026-09-17')['2026-09-17'];
    expect(entry?.kg, 64.8);
    expect(entry?.bodyFatPct, 17.9);
    expect(entry?.synced, isTrue);
  });

  group('删除与 tombstone 下行（2026-09-29 拍板）', () {
    test('上行回填 serverId；删除已同步条目 → tombstone → DELETE ack 后物理清除', () async {
      await store.save('2026-09-17', 65.5);
      adapter.stub(
        '/weight-logs',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{'id': 'srv-w1'}),
        ),
      );
      await sync.pushPending(store);
      // serverId 回填（删除定位用）。
      expect(
        store.loadEntries('2026-09-17', '2026-09-17')['2026-09-17']?.serverId,
        'srv-w1',
      );

      // 删除：置 tombstone——展示层即时排除、不入上行队列、保留待 DELETE。
      expect(await store.remove('2026-09-17'), isTrue);
      expect(store.loadEntries('2026-09-17', '2026-09-17'), isEmpty);
      expect(store.pendingEntries(), isEmpty);
      expect(store.pendingDeletions(), hasLength(1));

      adapter.stub(
        '/weight-logs/srv-w1',
        StubResponse.json(200, StubResponse.envelope(<String, dynamic>{})),
      );
      await sync.pushDeletions(store);
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.path, '/weight-logs/srv-w1');
      expect(store.pendingDeletions(), isEmpty);
      expect(store.recordCount(), 0);
    });

    test('删除未上行条目：直接物理移除，零网络请求；DELETE 404 按已删除清除', () async {
      await store.save('2026-09-18', 70.0); // 从未上行
      expect(await store.remove('2026-09-18'), isTrue);
      expect(store.recordCount(), 0);
      expect(store.pendingDeletions(), isEmpty);
      expect(adapter.requestBodies, isEmpty);

      // 404：服务端本无此行 → 本地 tombstone 清除。
      await store.save('2026-09-19', 71.0);
      final cid = store.pendingEntries().single.value.clientRequestId;
      await store.markSynced('2026-09-19', cid, serverId: 'srv-gone');
      await store.remove('2026-09-19');
      adapter.stub(
        '/weight-logs/srv-gone',
        StubResponse.json(404, <String, dynamic>{
          'error': <String, dynamic>{'code': 'NOT_FOUND', 'message': 'x'},
        }),
      );
      await sync.pushDeletions(store);
      expect(store.pendingDeletions(), isEmpty);
      expect(store.recordCount(), 0);
    });

    test(
      '下行 tombstones：移除本地已同步条目；本地 pending 同日保留；同日 logs+tombstone 并存终态为新值',
      () async {
        // 本地两条：09-20 已 synced（他端已删）、09-21 pending（本机未同步写入）。
        await store.save('2026-09-20', 65.0);
        await store.markSynced(
          '2026-09-20',
          store.pendingEntries().single.value.clientRequestId,
          serverId: 'srv-a',
        );
        await store.save('2026-09-21', 66.0);
        adapter.stub(
          '/weight-logs',
          StubResponse.json(
            200,
            StubResponse.envelope(<String, dynamic>{
              'logs': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'srv-b',
                  'date': '2026-09-22',
                  'weightKg': 67.5,
                  'bodyFatPct': null,
                  'updatedAt': '2999-09-22T01:00:00.000Z',
                },
              ],
              'tombstones': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'srv-a',
                  'date': '2026-09-20',
                  'deletedAt': '2026-09-22T02:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'srv-c',
                  'date': '2026-09-21',
                  'deletedAt': '2026-09-22T02:00:00.000Z',
                },
              ],
            }),
          ),
        );

        await sync.pullDown(store);

        final entries = store.loadEntries('2026-09-20', '2026-09-22');
        expect(
          entries.containsKey('2026-09-20'),
          isFalse,
          reason: 'tombstone 移除已同步条目',
        );
        expect(
          entries['2026-09-21']?.kg,
          66.0,
          reason: '本地 pending 优先，不被远端删除覆盖',
        );
        expect(entries['2026-09-22']?.kg, 67.5);
        expect(store.pendingEntries(), hasLength(1));
      },
    );
  });
}

import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { SyncService } from '../src/sync/sync.service';

/** waterLog 轻量两态同步（PRD M3 功能点 4）：create/delete 幂等 + 随 /sync/pull 下行 */
describe('sync：waterLog op（轻量两态，无 update）', () => {
  let store: DataStore;
  let sync: SyncService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    sync = new SyncService(store, new NutritionService(store));
    userId = store.createUser({ phone: '+8613800138000' }).id;
  });

  function createWaterOp(clientRequestId = randomUUID()) {
    return {
      clientRequestId,
      entity: 'waterLog',
      op: 'create',
      payload: {
        amountMl: 300,
        loggedAt: '2026-07-29T01:00:00.000Z',
        localDate: '2026-07-29',
      },
    };
  }

  it('create applied：落库并返回服务端视图（含 serverId/version）', () => {
    const res = sync.push(userId, [createWaterOp()]);
    const r = res.results[0];
    expect(r.status).toBe('applied');
    const view = r.serverEntry as { id: string; amountMl: number; version: number };
    expect(view.id).toBeTruthy();
    expect(view.amountMl).toBe(300);
    expect(view.version).toBe(1);
    expect(store.waterLogs.size).toBe(1);
  });

  it('create 幂等：同 clientRequestId 重放返回首次结果，不重复落库', () => {
    const op = createWaterOp();
    const first = sync.push(userId, [op]).results[0];
    const second = sync.push(userId, [op]).results[0];
    expect(second.status).toBe('applied');
    expect((second.serverEntry as { id: string }).id).toBe(
      (first.serverEntry as { id: string }).id,
    );
    expect(store.waterLogs.size).toBe(1);
  });

  it('create 同键不同体 → IDEMPOTENCY_PAYLOAD_MISMATCH', () => {
    const op = createWaterOp();
    sync.push(userId, [op]);
    const res = sync.push(userId, [{ ...op, payload: { ...op.payload, amountMl: 500 } }]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    expect(store.waterLogs.size).toBe(1);
  });

  it('create 缺 amountMl/loggedAt → VALIDATION_ERROR', () => {
    const res = sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'waterLog', op: 'create', payload: {} },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');
  });

  it('delete：按 serverId 软删；重复删除幂等返回 applied', () => {
    const created = sync.push(userId, [createWaterOp()]).results[0];
    const serverId = (created.serverEntry as { id: string }).id;
    const del = {
      clientRequestId: randomUUID(),
      entity: 'waterLog',
      op: 'delete',
      serverId,
    };
    expect(sync.push(userId, [del]).results[0].status).toBe('applied');
    expect(store.waterLogs.get(serverId)!.deletedAt).not.toBeNull();
    // 幂等：再次删除仍 applied
    expect(sync.push(userId, [{ ...del, clientRequestId: randomUUID() }]).results[0].status).toBe(
      'applied',
    );
  });

  it('delete：serverId 丢失时按 payload.clientRequestId 兜底定位（响应丢失场景）', () => {
    const rowKey = randomUUID();
    sync.push(userId, [createWaterOp(rowKey)]);
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'waterLog',
        op: 'delete',
        payload: { clientRequestId: rowKey },
      },
    ]);
    expect(res.results[0].status).toBe('applied');
    expect([...store.waterLogs.values()][0].deletedAt).not.toBeNull();
  });

  it('delete 未知记录 → NOT_FOUND（客户端据此丢弃本地 tombstone）', () => {
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'waterLog',
        op: 'delete',
        serverId: 'w-ghost',
      },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('NOT_FOUND');
  });

  it('update op 不支持 → VALIDATION_ERROR（两态无编辑场景）', () => {
    const res = sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'waterLog', op: 'update', payload: {} },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');
  });

  it('/sync/pull：waterLogChanges 含新建与 tombstone，且与 foodEntry 互不影响', async () => {
    const created = sync.push(userId, [createWaterOp()]).results[0];
    const serverId = (created.serverEntry as { id: string }).id;

    const pull1 = sync.pull(userId, undefined);
    expect(pull1.waterLogChanges.length).toBe(1);
    expect((pull1.waterLogChanges[0] as { amountMl: number }).amountMl).toBe(300);
    expect(pull1.changes.length).toBe(0); // 无 foodEntry

    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'waterLog', op: 'delete', serverId },
    ]);

    const pull2 = sync.pull(userId, pull1.syncToken);
    expect(pull2.waterLogChanges.length).toBe(1);
    const tomb = pull2.waterLogChanges[0] as { tombstone: { id: string; entity: string } };
    expect(tomb.tombstone.id).toBe(serverId);
    expect(tomb.tombstone.entity).toBe('waterLog');
  });

  it('他用户数据隔离：pull 不返回他人 waterLog', () => {
    const otherId = store.createUser({ phone: '+8613900139000' }).id;
    sync.push(otherId, [createWaterOp()]);
    const pull = sync.pull(userId, undefined);
    expect(pull.waterLogChanges.length).toBe(0);
  });
});

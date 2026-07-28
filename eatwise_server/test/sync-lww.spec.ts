import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { SyncService } from '../src/sync/sync.service';

/** LWW 版本冲突与增量下行（D-20 / 规格 §2.3 §2.4 §3） */
describe('sync：LWW 版本冲突 + syncToken 增量下行', () => {
  let store: DataStore;
  let sync: SyncService;
  let userId: string;
  let foodId: string;

  beforeEach(() => {
    store = new DataStore();
    sync = new SyncService(store, new NutritionService(store));
    userId = store.createUser({ phone: '+8613800138000' }).id;
    foodId = [...store.foods.values()][0].id;
  });

  function createEntry(): { id: string; version: number } {
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'create',
        payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 200 },
      },
    ]);
    return res.results[0].serverEntry as { id: string; version: number };
  }

  it('baseVersion 不符 → conflict version_mismatch 并返回服务端现值', () => {
    const entry = createEntry(); // version 1
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'update',
        serverId: entry.id,
        baseVersion: 3, // 过期版本
        payload: { id: entry.id, grams: 150 },
      },
    ]);
    const r = res.results[0];
    expect(r.status).toBe('conflict');
    expect(r.conflictType).toBe('version_mismatch');
    expect((r.serverEntry as { version: number }).version).toBe(1);
    expect((r.serverEntry as { grams: number }).grams).toBe(200); // 服务端现值未被覆盖
  });

  it('baseVersion 匹配 → applied，version +1，updatedAt 由服务端时钟赋值', () => {
    const entry = createEntry();
    const before = store.foodEntries.get(entry.id)!.updatedAt.getTime();
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'update',
        serverId: entry.id,
        baseVersion: 1,
        payload: { id: entry.id, grams: 150 },
      },
    ]);
    const r = res.results[0];
    expect(r.status).toBe('applied');
    const updated = r.serverEntry as {
      version: number;
      grams: number;
      nutritionSnapshot: { kcal: number };
    };
    expect(updated.version).toBe(2);
    expect(updated.grams).toBe(150);
    expect(store.foodEntries.get(entry.id)!.updatedAt.getTime()).toBeGreaterThanOrEqual(before);
    // 份量变化 → 营养快照重算（鸡蛋 144kcal/100g × 1.5 = 216）
    expect(updated.nutritionSnapshot.kcal).toBe(216);
  });

  it('一端删除另一端修改 → conflict deleted_vs_modified（不可合并，双份保留）', () => {
    const entry = createEntry();
    sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'delete',
        serverId: entry.id,
        baseVersion: 1,
      },
    ]);
    const res = sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'update',
        serverId: entry.id,
        baseVersion: 2,
        payload: { id: entry.id, grams: 150 },
      },
    ]);
    expect(res.results[0].status).toBe('conflict');
    expect(res.results[0].conflictType).toBe('deleted_vs_modified');
  });

  it('删除幂等：重复删除返回 applied', () => {
    const entry = createEntry();
    const op = {
      clientRequestId: randomUUID(),
      entity: 'foodEntry',
      op: 'delete',
      serverId: entry.id,
      baseVersion: 1,
    };
    expect(sync.push(userId, [op]).results[0].status).toBe('applied');
    expect(sync.push(userId, [{ ...op, clientRequestId: randomUUID() }]).results[0].status).toBe(
      'applied',
    );
  });

  it('增量下行：syncToken 之后只返回新变更，删除返回 tombstone', async () => {
    const e1 = createEntry();
    const pull1 = sync.pull(userId, undefined);
    expect(pull1.changes.length).toBe(1);
    expect(pull1.hasMore).toBe(false);

    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    const e2 = createEntry();
    sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'delete',
        serverId: e1.id,
        baseVersion: 1,
      },
    ]);
    void e2;

    const pull2 = sync.pull(userId, pull1.syncToken);
    expect(pull2.changes.length).toBe(2); // 1 条新建 + 1 条 tombstone
    const tombstones = pull2.changes.filter((c) => 'tombstone' in c);
    expect(tombstones.length).toBe(1);
    expect((tombstones[0] as { tombstone: { id: string } }).tombstone.id).toBe(e1.id);
  });

  it('非法 / 过期 syncToken → 400 INVALID_SYNC_TOKEN', () => {
    expect(() => sync.pull(userId, 'st_!!!bad')).toThrow(
      expect.objectContaining({ code: 'INVALID_SYNC_TOKEN' }) as unknown as Error,
    );
    const expired = `st_${Buffer.from(JSON.stringify({ ts: Date.now() - 31 * 24 * 3600 * 1000, id: '' })).toString('base64url')}`;
    expect(() => sync.pull(userId, expired)).toThrow(
      expect.objectContaining({ code: 'INVALID_SYNC_TOKEN' }) as unknown as Error,
    );
  });

  it('单批 >100 条由 DTO 层拒绝（ArrayMaxSize(100)）——服务层按批处理逐条返回', () => {
    // 服务层契约：逐条结果、整体不失败；>100 的 400 由 class-validator 在 Controller 入口保证
    const ops = Array.from({ length: 3 }, () => ({
      clientRequestId: randomUUID(),
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 100 },
    }));
    const res = sync.push(userId, ops);
    expect(res.results.length).toBe(3);
    expect(res.results.every((r) => r.status === 'applied')).toBe(true);
  });
});

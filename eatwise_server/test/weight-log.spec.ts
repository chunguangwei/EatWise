import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { WeightService } from '../src/weight/weight.service';

/** 体重记录（阶段 C）：幂等 upsert（同日覆写）+ 区间查询 + 软删（内存驱动口径） */
describe('WeightService（体重记录，内存驱动）', () => {
  let store: DataStore;
  let service: WeightService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    service = new WeightService(new MemoryStoreDriver(store));
    userId = store.createUser({ phone: '+8613800138000' }).id;
  });

  const dto = (over: Record<string, unknown> = {}) => ({
    clientRequestId: randomUUID(),
    date: '2026-09-17',
    weightKg: 65.5,
    ...over,
  });

  it('创建：落库并返回视图（含 id/version/bodyFatPct）', async () => {
    const view = await service.upsert(userId, dto({ bodyFatPct: 18.2 }));
    expect(view.id).toBeTruthy();
    expect(view.weightKg).toBe(65.5);
    expect(view.bodyFatPct).toBe(18.2);
    expect(view.version).toBe(1);
    expect(store.weightLogs.size).toBe(1);
  });

  it('幂等：同 clientRequestId 重放返回首次结果，不重复落库', async () => {
    const body = dto();
    const first = await service.upsert(userId, body);
    const replay = await service.upsert(userId, body);
    expect(replay.id).toBe(first.id);
    expect(store.weightLogs.size).toBe(1);
  });

  it('同键不同体 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const body = dto();
    await service.upsert(userId, body);
    await expect(service.upsert(userId, { ...body, weightKg: 66 })).rejects.toMatchObject({
      code: 'IDEMPOTENCY_PAYLOAD_MISMATCH',
    });
    expect(store.weightLogs.size).toBe(1);
  });

  it('同日覆写：新 clientRequestId 同 date → 更新同一行，version+1，重放按新键命中', async () => {
    const first = await service.upsert(userId, dto({ weightKg: 70 }));
    const second = await service.upsert(userId, dto({ weightKg: 69.4, bodyFatPct: null }));
    expect(second.id).toBe(first.id);
    expect(second.weightKg).toBe(69.4);
    expect(second.version).toBe(2);
    expect(store.weightLogs.size).toBe(1);
    // 旧幂等键不再命中（换绑新键）；新键重放返回覆写后结果
    const replay = await service.upsert(userId, {
      clientRequestId: second.clientRequestId,
      date: '2026-09-17',
      weightKg: 69.4,
    });
    expect(replay.id).toBe(first.id);
  });

  it('非法日期（13 月 / 格式错）→ VALIDATION_ERROR', async () => {
    await expect(service.upsert(userId, dto({ date: '2026-13-01' }))).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
    await expect(service.list(userId, '2026-09-40', '2026-09-17')).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
    await expect(service.list(userId, '2026-09-18', '2026-09-17')).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
  });

  it('区间查询：含端点、date 升序、排除 tombstone 与他用户', async () => {
    await service.upsert(userId, dto({ date: '2026-09-15', weightKg: 66 }));
    await service.upsert(userId, dto({ date: '2026-09-17', weightKg: 65.5 }));
    await service.upsert(userId, dto({ date: '2026-09-16', weightKg: 65.8 }));
    const otherId = store.createUser({ phone: '+8613900139000' }).id;
    await service.upsert(otherId, dto({ date: '2026-09-16', weightKg: 80 }));

    const res = await service.list(userId, '2026-09-15', '2026-09-16');
    expect(res.logs.map((l) => l.date)).toEqual(['2026-09-15', '2026-09-16']);

    // 软删后区间查询排除
    const target = (await service.list(userId, '2026-09-16', '2026-09-16')).logs[0];
    await service.remove(userId, target.id);
    expect((await service.list(userId, '2026-09-15', '2026-09-17')).logs).toHaveLength(2);
  });

  it('软删：重复删除幂等；他人记录/不存在 → NOT_FOUND', async () => {
    const view = await service.upsert(userId, dto());
    const deleted = await service.remove(userId, view.id);
    expect(deleted.deletedAt).toBeTruthy();
    expect(deleted.version).toBe(2);
    // 幂等：再次删除仍成功（不重复 bump 由调用方无感，version 不再涨）
    const again = await service.remove(userId, view.id);
    expect(again.version).toBe(2);

    const otherId = store.createUser({ phone: '+8613900139001' }).id;
    await expect(service.remove(otherId, view.id)).rejects.toMatchObject({ code: 'NOT_FOUND' });
    await expect(service.remove(userId, 'w-missing')).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });

  it('软删后同日可重新记录（新行）', async () => {
    const first = await service.upsert(userId, dto());
    await service.remove(userId, first.id);
    const recreated = await service.upsert(userId, dto({ weightKg: 64.9 }));
    expect(recreated.id).not.toBe(first.id);
    expect(store.weightLogs.size).toBe(2); // tombstone + 新行
    const list = await service.list(userId, '2026-09-17', '2026-09-17');
    expect(list.logs).toHaveLength(1);
    expect(list.logs[0].weightKg).toBe(64.9);
  });
});

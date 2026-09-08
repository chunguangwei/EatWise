import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { newId } from '../src/common/utils/id.util';
import { addDays, localDateOf } from '../src/common/utils/time.util';
import { StreakService } from '../src/streak/streak.service';

const TZ = 'Asia/Shanghai';

describe('streak 与补签卡（D-12）', () => {
  let store: DataStore;
  let streak: StreakService;
  let userId: string;
  let today: string;

  beforeEach(() => {
    store = new DataStore();
    streak = new StreakService(new MemoryStoreDriver(store));
    userId = store.createUser({ phone: '+8613800138000', timezone: TZ }).id;
    today = localDateOf(new Date(), TZ);
  });

  function addQualifiedRecord(date: string) {
    const now = new Date();
    const record: FastingRecordEntity = {
      id: newId(),
      userId,
      attributionDate: date,
      plannedStartAt: now,
      plannedEndAt: now,
      actualStartAt: now,
      actualEndAt: now,
      extendedMinutes: 0,
      fastedMinutes: 960,
      result: 'completed',
      isQualified: true,
      eventLog: [],
      clientRequestId: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
    };
    store.fastingRecords.set(record.id, record);
  }

  it('首次访问：补签卡库存 2 张（每月 1 日发放，上限 2）', async () => {
    const s = await streak.getOrCreate(userId, TZ);
    expect(s.makeupCards.stock).toBe(2);
    expect(s.makeupCards.month).toBe(today.slice(0, 7));
  });

  it('进入新月：月底清零、月初重发 2 张、usedDates 清空', async () => {
    const s = await streak.getOrCreate(userId, TZ);
    s.makeupCards.stock = 0;
    s.makeupCards.usedDates = ['2026-06-20'];
    s.makeupCards.month = '2000-01'; // 模拟上月遗留
    const rolled = await streak.getOrCreate(userId, TZ);
    expect(rolled.makeupCards.stock).toBe(2);
    expect(rolled.makeupCards.usedDates).toEqual([]);
  });

  it('补签成功：库存 -1、生成 makeup 留痕记录、streak 重算连回', async () => {
    const date = addDays(today, -1);
    const res = (await streak.makeUp(userId, randomUUID(), date)) as {
      currentStreak: number;
      makeupCards: { stock: number };
    };
    expect(res.makeupCards.stock).toBe(1);
    expect(res.currentStreak).toBe(1);
    const marker = [...store.fastingRecords.values()].find((r) => r.result === 'makeup');
    expect(marker?.attributionDate).toBe(date);
  });

  it('断签中断后补签可把 streak 连回（达标 2 天 + 断 1 天 + 补签）', async () => {
    addQualifiedRecord(addDays(today, -3));
    addQualifiedRecord(addDays(today, -2));
    // 昨天断签 → 补签
    await streak.recompute(userId);
    expect((await streak.getOrCreate(userId)).currentStreak).toBe(0); // 中断归零
    const res = (await streak.makeUp(userId, randomUUID(), addDays(today, -1))) as {
      currentStreak: number;
    };
    expect(res.currentStreak).toBe(3);
  });

  it('仅可补最近 7 天内：第 8 天前 → 400 MAKEUP_OUT_OF_WINDOW', async () => {
    await expect(streak.makeUp(userId, randomUUID(), addDays(today, -8))).rejects.toThrow(
      expect.objectContaining({ code: 'MAKEUP_OUT_OF_WINDOW' }) as unknown as Error,
    );
  });

  it('不能补今天（断食可能仍在进行）→ MAKEUP_OUT_OF_WINDOW', async () => {
    await expect(streak.makeUp(userId, randomUUID(), today)).rejects.toThrow(
      expect.objectContaining({ code: 'MAKEUP_OUT_OF_WINDOW' }) as unknown as Error,
    );
  });

  it('重复补同一日期 → 409 MAKEUP_ALREADY_USED', async () => {
    const date = addDays(today, -1);
    await streak.makeUp(userId, randomUUID(), date);
    await expect(streak.makeUp(userId, randomUUID(), date)).rejects.toThrow(
      expect.objectContaining({ code: 'MAKEUP_ALREADY_USED' }) as unknown as Error,
    );
  });

  it('已达标的日期无需补签 → MAKEUP_ALREADY_USED', async () => {
    const date = addDays(today, -1);
    addQualifiedRecord(date);
    await expect(streak.makeUp(userId, randomUUID(), date)).rejects.toThrow(
      expect.objectContaining({ code: 'MAKEUP_ALREADY_USED' }) as unknown as Error,
    );
  });

  it('库存用尽（上限 2 张）→ 400 MAKEUP_CARD_EMPTY', async () => {
    await streak.makeUp(userId, randomUUID(), addDays(today, -1));
    await streak.makeUp(userId, randomUUID(), addDays(today, -2));
    await expect(streak.makeUp(userId, randomUUID(), addDays(today, -3))).rejects.toThrow(
      expect.objectContaining({ code: 'MAKEUP_CARD_EMPTY' }) as unknown as Error,
    );
  });

  it('补签幂等：同 clientRequestId 重放返回首次结果，不重复扣卡', async () => {
    const date = addDays(today, -1);
    const clientRequestId = randomUUID();
    const first = await streak.makeUp(userId, clientRequestId, date);
    const replay = await streak.makeUp(userId, clientRequestId, date);
    expect(replay).toEqual(first);
    expect((await streak.getOrCreate(userId)).makeupCards.stock).toBe(1);
  });

  it('里程碑：currentStreak 跨越 3/7/30 时写入', async () => {
    for (let i = 1; i <= 7; i++) addQualifiedRecord(addDays(today, -i));
    const s = await streak.recompute(userId);
    expect(s.currentStreak).toBe(7);
    expect(s.milestones['3']).toBeTruthy();
    expect(s.milestones['7']).toBeTruthy();
    expect(s.milestones['30']).toBeUndefined();
  });
});

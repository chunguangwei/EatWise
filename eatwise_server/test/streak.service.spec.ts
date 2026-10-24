import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { newId } from '../src/common/utils/id.util';
import { addDays, localDateOf } from '../src/common/utils/time.util';
import { StreakService } from '../src/streak/streak.service';

const TZ = 'Asia/Shanghai';

describe('streak 与补签卡（D-12）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let streak: StreakService;
  let userId: string;
  let today: string;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    streak = new StreakService(driver);
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
      deletedAt: null,
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
    await driver.saveStreak(s); // 驱动读取返回副本（与 prisma 同语义），改动须显式落库
    const rolled = await streak.getOrCreate(userId, TZ);
    expect(rolled.makeupCards.stock).toBe(2);
    expect(rolled.makeupCards.usedDates).toEqual([]);
  });

  it('recompute 与 makeUp 自身也会纠正滞后月份，S1 窗口常量保持 7', async () => {
    const stale = await streak.getOrCreate(userId, TZ);
    stale.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await driver.saveStreak(stale);
    await streak.recompute(userId);
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: today.slice(0, 7),
      usedDates: [],
    });

    const staleAgain = await driver.findStreakByUser(userId);
    staleAgain!.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await driver.saveStreak(staleAgain!);
    const response = (await streak.makeUp(userId, randomUUID(), addDays(today, -1))) as {
      makeupCards: { stock: number; usableWindowDays: number };
    };
    expect(response.makeupCards.stock).toBe(1);
    expect(response.makeupCards.usableWindowDays).toBe(7);
  });

  it('断档/重新开始不额外送卡；跨月未用完也只重置为 2 不叠加', async () => {
    const current = await streak.getOrCreate(userId, TZ);
    current.makeupCards.stock = 1;
    await driver.saveStreak(current);
    addQualifiedRecord(addDays(today, -3));
    await streak.recompute(userId);
    expect((await driver.findStreakByUser(userId))?.makeupCards.stock).toBe(1);
    addQualifiedRecord(today);
    await streak.recompute(userId);
    expect((await driver.findStreakByUser(userId))?.makeupCards.stock).toBe(1);

    const previousMonth = await driver.findStreakByUser(userId);
    previousMonth!.makeupCards = { stock: 1, month: '2000-01', usedDates: [] };
    await driver.saveStreak(previousMonth!);
    expect((await streak.getOrCreate(userId, TZ)).makeupCards.stock).toBe(2);
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

  it('7 天窗口 parity：D+6 可补，D+7/D+8 均 MAKEUP_OUT_OF_WINDOW', async () => {
    await streak.makeUp(userId, randomUUID(), addDays(today, -6));
    expect((await driver.findStreakByUser(userId))?.makeupCards.stock).toBe(1);
    for (const date of [addDays(today, -7), addDays(today, -8)]) {
      await expect(streak.makeUp(userId, randomUUID(), date)).rejects.toThrow(
        expect.objectContaining({ code: 'MAKEUP_OUT_OF_WINDOW' }) as unknown as Error,
      );
    }
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

  it('补签扣减持久化：重新读取（全新对象）库存已 -1 且 usedDates 留痕', async () => {
    // 回归钉（wcg 2026-10-07：补签成功但库存仍 2 张）——makeUp 原地扣减后
    // 必须 saveStreak 落库；prisma 驱动每次读取映射新对象，漏 save 即丢失。
    const date = addDays(today, -1);
    await streak.makeUp(userId, randomUUID(), date);
    const fresh = await driver.findStreakByUser(userId);
    expect(fresh?.makeupCards.stock).toBe(1);
    expect(fresh?.makeupCards.usedDates).toEqual([date]);
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

  it('补签日期必须是真实日历日：2026-02-29 → VALIDATION_ERROR', async () => {
    await expect(streak.makeUp(userId, randomUUID(), '2026-02-29')).rejects.toThrow(
      expect.objectContaining({ code: 'VALIDATION_ERROR' }) as unknown as Error,
    );
    expect([...store.fastingRecords.values()].filter((r) => r.result === 'makeup')).toHaveLength(0);
    expect((await streak.getOrCreate(userId)).makeupCards.stock).toBe(2);
  });

  it('同键并发补签只扣一次并只生成一个 marker', async () => {
    const clientRequestId = randomUUID();
    const date = addDays(today, -1);
    const [first, replay] = await Promise.all([
      streak.makeUp(userId, clientRequestId, date),
      streak.makeUp(userId, clientRequestId, date),
    ]);
    expect(replay).toEqual(first);
    const fresh = await driver.findStreakByUser(userId);
    expect(fresh?.makeupCards.stock).toBe(1);
    expect(fresh?.makeupCards.usedDates).toEqual([date]);
    expect([...store.fastingRecords.values()].filter((r) => r.result === 'makeup')).toHaveLength(1);
  });

  it('并发补签与 recompute 不用旧快照覆盖 cards', async () => {
    const dates = [addDays(today, -1), addDays(today, -2)];
    await Promise.all([
      streak.makeUp(userId, randomUUID(), dates[0]),
      streak.makeUp(userId, randomUUID(), dates[1]),
      streak.recompute(userId),
      streak.recompute(userId),
    ]);
    const fresh = await driver.findStreakByUser(userId);
    expect(fresh?.makeupCards.stock).toBe(0);
    expect(fresh?.makeupCards.usedDates.sort()).toEqual([...dates].sort());
    expect(fresh?.currentStreak).toBe(2);
    expect([...store.fastingRecords.values()].filter((r) => r.result === 'makeup')).toHaveLength(2);
  });

  it('跨时区月初按用户本地月 rollover，UTC 尚未进入新月时不提前发', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-02-28T16:30:00.000Z'));
    try {
      const stale = await streak.getOrCreate(userId, TZ);
      stale.makeupCards = { stock: 0, month: '2026-02', usedDates: ['2026-02-20'] };
      await driver.saveStreak(stale);
      const shanghai = await streak.getOrCreate(userId, TZ);
      expect(shanghai.makeupCards).toEqual({ stock: 2, month: '2026-03', usedDates: [] });

      shanghai.makeupCards = { stock: 0, month: '2026-02', usedDates: ['2026-02-20'] };
      await driver.saveStreak(shanghai);
      const utc = await streak.getOrCreate(userId, 'UTC');
      expect(utc.makeupCards).toEqual({ stock: 0, month: '2026-02', usedDates: ['2026-02-20'] });
    } finally {
      jest.useRealTimers();
    }
  });

  it('重复调用不叠加；滞后月份并发读取只 rollover 一次语义且库存不超过 2', async () => {
    const current = await streak.getOrCreate(userId, TZ);
    current.makeupCards.stock = 1;
    await driver.saveStreak(current);
    const repeated = await Promise.all(
      Array.from({ length: 8 }, () => streak.getOrCreate(userId, TZ)),
    );
    expect(repeated.every((s) => s.makeupCards.stock === 1)).toBe(true);

    const stale = await driver.findStreakByUser(userId);
    stale!.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await driver.saveStreak(stale!);
    const rolled = await Promise.all(
      Array.from({ length: 12 }, () => streak.getOrCreate(userId, TZ)),
    );
    expect(rolled.every((s) => s.makeupCards.stock === 2)).toBe(true);
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: today.slice(0, 7),
      usedDates: [],
    });

    const corrupted = await driver.findStreakByUser(userId);
    corrupted!.makeupCards.stock = 9;
    await driver.saveStreak(corrupted!);
    expect((await streak.getOrCreate(userId, TZ)).makeupCards.stock).toBe(2);
  });
});

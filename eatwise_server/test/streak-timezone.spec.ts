import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StreakController } from '../src/streak/streak.controller';
import { StreakService } from '../src/streak/streak.service';
import { SyncController } from '../src/sync/sync.controller';
import { SyncService } from '../src/sync/sync.service';

describe('streak rollover 请求时区', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let streak: StreakService;
  let streakController: StreakController;
  let syncController: SyncController;
  let userId: string;

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-02-28T16:30:00.000Z'));
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    streak = new StreakService(driver);
    streakController = new StreakController(streak, driver);
    syncController = new SyncController(
      new SyncService(driver, new NutritionService(driver), streak, new ConfigService()),
      driver,
    );
    userId = store.createUser({ phone: '+8613800138000', timezone: 'UTC' }).id;
  });

  afterEach(() => jest.useRealTimers());

  async function makeStale() {
    const entity = await streak.getOrCreate(userId, 'UTC');
    entity.makeupCards = { stock: 0, month: '2026-02', usedDates: ['2026-02-20'] };
    await driver.saveStreak(entity);
  }

  it('S1 使用合法 X-Timezone 做 recompute/rollover，不被 profile UTC 翻回旧月', async () => {
    await makeStale();
    await streakController.get({ userId }, 'Asia/Shanghai');
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: '2026-03',
      usedDates: [],
    });
  });

  it('S2 与客户端本地日一致：上海已是次日可补，UTC 当天口径不会误拒绝', async () => {
    await makeStale();
    const response = (await streakController.makeUp(
      { userId },
      { clientRequestId: randomUUID(), date: '2026-02-28' },
      'Asia/Shanghai',
    )) as { makeupCards: { stock: number; usableWindowDays: number } };
    expect(response.makeupCards.stock).toBe(1);
    expect(response.makeupCards.usableWindowDays).toBe(7);
    expect((await driver.findStreakByUser(userId))?.makeupCards.month).toBe('2026-03');
  });

  it('sync push 内部 recompute 与 pull 都沿用请求时区 rollover', async () => {
    await makeStale();
    await syncController.push(
      { userId },
      {
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'create',
            payload: {
              attributionDate: '2026-02-20',
              plannedStartAt: '2026-02-19T12:00:00.000Z',
              plannedEndAt: '2026-02-20T04:00:00.000Z',
              actualStartAt: '2026-02-19T12:00:00.000Z',
              actualEndAt: '2026-02-20T04:00:00.000Z',
              result: 'completed',
              isQualified: true,
            },
          },
        ],
      },
      'Asia/Shanghai',
    );
    expect((await driver.findStreakByUser(userId))?.makeupCards.month).toBe('2026-03');

    await makeStale();
    await syncController.pull({ userId }, undefined, undefined, 'Asia/Shanghai');
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: '2026-03',
      usedDates: [],
    });
  });
});

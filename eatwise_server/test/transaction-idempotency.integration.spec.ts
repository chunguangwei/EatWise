import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { FastingRecordEntity } from '../src/common/store/data-store';
import { PrismaStore } from '../src/common/store/prisma-store';
import { StoreDriver } from '../src/common/store/store-driver';
import { addDays, localDateOf } from '../src/common/utils/time.util';
import { FastingService } from '../src/fasting/fasting.service';
import { FoodService } from '../src/food/food.service';
import { PrismaService } from '../src/infra/prisma.service';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { StreakService } from '../src/streak/streak.service';
import { SyncService } from '../src/sync/sync.service';

const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;
const describePg = RUN_PG ? describe : describe.skip;
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

jest.setTimeout(30000);

describePg('事务与幂等（真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let streak: StreakService;
  let fasting: FastingService;
  let sync: SyncService;
  let food: FoodService;
  let userId: string;
  const userIds = new Set<string>();
  const sharedFoodId = `it-transaction-food-${randomUUID()}`;

  async function createUser(timezone = 'Asia/Shanghai'): Promise<string> {
    const user = await store.createUser({ phone: randomUUID(), timezone });
    userIds.add(user.id);
    return user.id;
  }

  function ongoingRecord(): FastingRecordEntity {
    const now = new Date();
    return {
      id: randomUUID(),
      userId,
      attributionDate: localDateOf(now, 'Asia/Shanghai'),
      plannedStartAt: new Date(now.getTime() - 16 * 3600000),
      plannedEndAt: new Date(now.getTime() + 3600000),
      actualStartAt: new Date(now.getTime() - 16 * 3600000),
      actualEndAt: null,
      extendedMinutes: 0,
      fastedMinutes: null,
      result: 'on_track',
      isQualified: false,
      eventLog: [],
      clientRequestId: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
  }

  beforeAll(async () => {
    prisma = new PrismaService(new ConfigService());
    await prisma.$connect();
    store = new PrismaStore(prisma);
    await store.upsertFoods([
      {
        id: sharedFoodId,
        nameZh: '事务集成测试食物',
        nameEn: 'Transaction integration food',
        aliases: [],
        kcalPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 20,
        fatPer100g: 5,
        category: '测试',
        source: 'cn_fct',
      },
    ]);
  });

  beforeEach(async () => {
    streak = new StreakService(store);
    fasting = new FastingService(store, new ConfigService(), streak);
    sync = new SyncService(store, new NutritionService(store), streak, new ConfigService());
    food = new FoodService(store, new StubModerationService());
    userId = await createUser();
  });

  afterEach(async () => {
    for (const id of userIds) await store.purgeUserData(id);
    userIds.clear();
  });

  afterAll(async () => {
    await prisma.food.deleteMany({ where: { id: sharedFoodId } });
    await prisma.$disconnect();
  });

  it('同键 advisory lock 串行，不同键事务可以并行', async () => {
    let sameActive = 0;
    let sameMax = 0;
    await Promise.all(
      ['first', 'second'].map((nickname) =>
        store.runInTransaction(['pg-same-key'], async (tx) => {
          sameActive += 1;
          sameMax = Math.max(sameMax, sameActive);
          try {
            await delay(40);
            await tx.updateUserProfile(userId, { nickname });
          } finally {
            sameActive -= 1;
          }
        }),
      ),
    );
    expect(sameMax).toBe(1);

    const otherId = await createUser();
    let differentActive = 0;
    let differentMax = 0;
    const run = (key: string, id: string) =>
      store.runInTransaction([key], async (tx) => {
        differentActive += 1;
        differentMax = Math.max(differentMax, differentActive);
        try {
          await delay(40);
          await tx.updateUserProfile(id, { nickname: key });
        } finally {
          differentActive -= 1;
        }
      });
    await Promise.all([run('pg-key-a', userId), run('pg-key-b', otherId)]);
    expect(differentMax).toBe(2);
  });

  it('异常回滚业务写与回执写，tx 内读取不会逃回 root', async () => {
    await expect(
      store.runInTransaction(['pg-rollback'], async (tx: StoreDriver) => {
        await tx.updateUserProfile(userId, { nickname: 'rolled-back' });
        expect((await tx.findUserById(userId))?.nickname).toBe('rolled-back');
        await tx.saveIdempotencyRecord({
          userId,
          endpoint: 'test/rollback',
          clientRequestId: randomUUID(),
          payloadHash: 'hash',
          responseBody: { ok: true },
          createdAt: new Date(),
        });
        throw new Error('force pg rollback');
      }),
    ).rejects.toThrow('force pg rollback');
    expect((await store.findUserById(userId))?.nickname).toBeNull();
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(0);
  });

  it('E1 同键并发只建一行；回执缺失后同体重建完整响应', async () => {
    const dto = {
      clientRequestId: randomUUID(),
      eatenAt: '2026-07-27T04:10:00.000Z',
      foodId: sharedFoodId,
      grams: 200,
      inputMethod: 'manual',
    };
    const [first, replay] = await Promise.all([
      sync.createEntry(userId, dto),
      sync.createEntry(userId, dto),
    ]);
    expect(replay).toEqual(first);
    expect(await prisma.foodEntry.count({ where: { userId } })).toBe(1);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(1);

    await prisma.idempotencyKey.deleteMany({ where: { userId } });
    const recovered = (await sync.createEntry(userId, dto)) as {
      entry: { id: string };
      dailyNutrition: { kcal: number };
    };
    expect(recovered.entry.id).toBe((first as { entry: { id: string } }).entry.id);
    expect(recovered.dailyNutrition.kcal).toBe(200);
    expect(await prisma.foodEntry.count({ where: { userId } })).toBe(1);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(1);
  });

  it('extend 同键重放和不同键并发均不双倍延长或丢更新', async () => {
    const record = ongoingRecord();
    await store.saveFastingRecord(record);
    const sameRequestId = randomUUID();
    const [first, replay] = await Promise.all([
      fasting.extend(userId, sameRequestId, record.id, 30),
      fasting.extend(userId, sameRequestId, record.id, 30),
    ]);
    expect(replay).toEqual(first);
    await Promise.all(
      Array.from({ length: 7 }, () => fasting.extend(userId, randomUUID(), record.id, 30)),
    );
    const stored = await store.findFastingRecordById(record.id);
    expect(stored?.extendedMinutes).toBe(240);
    expect(stored?.eventLog).toHaveLength(8);
    expect(stored?.version).toBe(9);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(8);
  });

  it('fastingRecord 同键重放忽略派生结果差异，锚点变化仍 mismatch', async () => {
    const op = {
      clientRequestId: randomUUID(),
      entity: 'fastingRecord',
      op: 'create',
      payload: {
        attributionDate: '2026-08-01',
        plannedStartAt: '2026-07-31T12:00:00.000Z',
        plannedEndAt: '2026-08-01T04:00:00.000Z',
        actualStartAt: '2026-07-31T12:00:00.000Z',
        actualEndAt: '2026-08-01T04:00:00.000Z',
        extendedMinutes: 0,
        result: 'completed',
        isQualified: true,
      },
    };
    await sync.push(userId, [op]);
    const derivedReplay = await sync.push(userId, [
      { ...op, payload: { ...op.payload, result: 'broken', isQualified: false } },
    ]);
    expect(derivedReplay.results[0].status).toBe('applied');
    const anchorReplay = await sync.push(userId, [
      { ...op, payload: { ...op.payload, plannedEndAt: '2026-08-01T05:00:00.000Z' } },
    ]);
    expect(anchorReplay.results[0].status).toBe('error');
    expect(anchorReplay.results[0].error?.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    expect(await prisma.fastingRecord.count({ where: { userId } })).toBe(1);
  });

  it('createCustomFood/contribute 同键并发与残留恢复不新增重复行', async () => {
    const createDto = {
      clientRequestId: randomUUID(),
      nameZh: 'PG 事务酸奶',
      nameEn: 'PG transactional yogurt',
      per100g: { kcal: 60, proteinG: 3.5, carbG: 7, fatG: 2.5 },
      source: 'manual' as const,
    };
    const [created, createdReplay] = await Promise.all([
      food.createCustomFood(userId, createDto),
      food.createCustomFood(userId, createDto),
    ]);
    expect(createdReplay).toEqual(created);
    const customId = (created as { id: string }).id;
    expect(await prisma.food.count({ where: { createdByUserId: userId, isCustom: true } })).toBe(1);

    await prisma.idempotencyKey.deleteMany({ where: { userId } });
    const recovered = (await food.createCustomFood(userId, createDto)) as { id: string };
    expect(recovered.id).toBe(customId);
    expect(await prisma.food.count({ where: { createdByUserId: userId, isCustom: true } })).toBe(1);

    await prisma.idempotencyKey.deleteMany({ where: { userId } });
    const contributeDto = { clientRequestId: randomUUID() };
    const [candidate, candidateReplay] = await Promise.all([
      food.contributeCustomFood(userId, customId, contributeDto),
      food.contributeCustomFood(userId, customId, contributeDto),
    ]);
    expect(candidateReplay).toEqual(candidate);
    expect(await prisma.foodCandidate.count({ where: { userId } })).toBe(1);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(1);
  });

  it('月度 rollover 并发读取即纠正；补签/recompute 并发不覆盖 cards', async () => {
    const initial = await streak.getOrCreate(userId);
    initial.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await store.saveStreak(initial);
    const rolled = await Promise.all(Array.from({ length: 10 }, () => streak.getOrCreate(userId)));
    expect(rolled.every((s) => s.makeupCards.stock === 2)).toBe(true);
    expect((await store.findStreakByUser(userId))?.makeupCards.stock).toBe(2);

    const today = localDateOf(new Date(), 'Asia/Shanghai');
    const sameRequestId = randomUUID();
    const [first, replay] = await Promise.all([
      streak.makeUp(userId, sameRequestId, addDays(today, -1)),
      streak.makeUp(userId, sameRequestId, addDays(today, -1)),
    ]);
    expect(replay).toEqual(first);
    expect((await store.findStreakByUser(userId))?.makeupCards.stock).toBe(1);

    await Promise.all([
      streak.makeUp(userId, randomUUID(), addDays(today, -2)),
      streak.recompute(userId),
      streak.recompute(userId),
    ]);
    const fresh = await store.findStreakByUser(userId);
    expect(fresh?.makeupCards.stock).toBe(0);
    expect(fresh?.makeupCards.usedDates.sort()).toEqual(
      [addDays(today, -1), addDays(today, -2)].sort(),
    );
    expect(await prisma.fastingRecord.count({ where: { userId, result: 'makeup' } })).toBe(2);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(2);
  });

  it('回执写失败时 extend/endFast/makeUp/createCustomFood/contribute 全部回滚', async () => {
    const expectReceiptFailure = async (work: () => Promise<unknown>) => {
      const spy = jest
        .spyOn(PrismaStore.prototype, 'saveIdempotencyRecord')
        .mockRejectedValueOnce(new Error('receipt failed'));
      try {
        await expect(work()).rejects.toThrow('receipt failed');
      } finally {
        spy.mockRestore();
      }
    };

    const extendRecord = ongoingRecord();
    await store.saveFastingRecord(extendRecord);
    await expectReceiptFailure(() => fasting.extend(userId, randomUUID(), extendRecord.id, 30));
    expect((await store.findFastingRecordById(extendRecord.id))?.extendedMinutes).toBe(0);
    expect((await store.findFastingRecordById(extendRecord.id))?.eventLog).toHaveLength(0);

    const endRecord = ongoingRecord();
    await store.saveFastingRecord(endRecord);
    await expectReceiptFailure(() =>
      fasting.endFast(userId, randomUUID(), endRecord.id, endRecord.plannedEndAt),
    );
    expect((await store.findFastingRecordById(endRecord.id))?.result).toBe('on_track');
    expect((await store.findFastingRecordById(endRecord.id))?.actualEndAt).toBeNull();

    const today = localDateOf(new Date(), 'Asia/Shanghai');
    await expectReceiptFailure(() => streak.makeUp(userId, randomUUID(), addDays(today, -1)));
    expect(await store.findStreakByUser(userId)).toBeNull();
    expect(await prisma.fastingRecord.count({ where: { userId, result: 'makeup' } })).toBe(0);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(0);

    const createDto = {
      clientRequestId: randomUUID(),
      nameZh: 'PG 回滚食物',
      nameEn: 'PG rollback food',
      per100g: { kcal: 60, proteinG: 3.5, carbG: 7, fatG: 2.5 },
      source: 'manual' as const,
    };
    await expectReceiptFailure(() => food.createCustomFood(userId, createDto));
    expect(await prisma.food.count({ where: { createdByUserId: userId, isCustom: true } })).toBe(0);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(0);

    const custom = await food.createCustomFood(userId, {
      ...createDto,
      clientRequestId: randomUUID(),
    });
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(1);
    await expectReceiptFailure(() =>
      food.contributeCustomFood(userId, (custom as { id: string }).id, {
        clientRequestId: randomUUID(),
      }),
    );
    expect(await prisma.foodCandidate.count({ where: { userId } })).toBe(0);
    expect(await prisma.idempotencyKey.count({ where: { userId } })).toBe(1);
  });
});

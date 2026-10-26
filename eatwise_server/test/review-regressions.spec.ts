import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver, StoreDriver } from '../src/common/store/store-driver';
import { PrismaStore } from '../src/common/store/prisma-store';
import { addDays, localDateOf } from '../src/common/utils/time.util';
import { FastingService } from '../src/fasting/fasting.service';
import { FoodService } from '../src/food/food.service';
import { PrismaService } from '../src/infra/prisma.service';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { StreakService } from '../src/streak/streak.service';
import { SyncService } from '../src/sync/sync.service';

const TZ = 'Asia/Shanghai';
const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;

for (const backend of ['memory', 'prisma'] as const) {
  const suite = backend === 'prisma' && !RUN_PG ? describe.skip : describe;
  suite(`审核回归：断食结算与并发写入 (${backend})`, () => {
    let driver: StoreDriver;
    let prisma: PrismaService | undefined;
    let userId: string;
    let fasting: FastingService;
    let streak: StreakService;
    let sync: SyncService;
    let food: FoodService;
    const foodIds = new Set<string>();

    beforeAll(async () => {
      if (backend === 'prisma') {
        prisma = new PrismaService(new ConfigService());
        await prisma.$connect();
      }
    });
    beforeEach(async () => {
      driver = prisma ? new PrismaStore(prisma) : new MemoryStoreDriver(new DataStore());
      userId = (await driver.createUser({ phone: randomUUID(), timezone: TZ })).id;
      streak = new StreakService(driver);
      fasting = new FastingService(driver, new ConfigService(), streak);
      sync = new SyncService(driver, new NutritionService(driver), streak, new ConfigService());
      food = new FoodService(driver, new StubModerationService());
    });
    afterEach(async () => {
      jest.restoreAllMocks();
      await driver.purgeUserData(userId);
      if (prisma) await prisma.food.deleteMany({ where: { id: { in: [...foodIds] } } });
      foodIds.clear();
    });
    afterAll(async () => {
      await prisma?.$disconnect();
    });

    function record(extendedMinutes = 60): FastingRecordEntity {
      const now = new Date();
      return {
        id: randomUUID(),
        userId,
        attributionDate: '2026-08-01',
        plannedStartAt: new Date('2026-07-31T12:00:00Z'),
        plannedEndAt: new Date(Date.parse('2026-08-01T04:00:00Z') + extendedMinutes * 60000),
        actualStartAt: new Date('2026-07-31T12:00:00Z'),
        actualEndAt: null,
        extendedMinutes,
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

    function payload(r = record()) {
      return {
        attributionDate: r.attributionDate,
        plannedStartAt: r.plannedStartAt.toISOString(),
        plannedEndAt: r.plannedEndAt.toISOString(),
        actualStartAt: r.actualStartAt!.toISOString(),
        actualEndAt: '2026-08-01T04:00:00.000Z',
        extendedMinutes: r.extendedMinutes,
        result: 'completed',
        isQualified: true,
      };
    }
    function push(p: Record<string, unknown>) {
      return sync.push(
        userId,
        [{ clientRequestId: randomUUID(), entity: 'fastingRecord', op: 'create', payload: p }],
        TZ,
      );
    }

    it.each([
      [60, '04:00:00', 'completed', true],
      [60, '03:59:59', 'broken', false],
      [60, '04:30:00', 'completed', true],
      [0, '03:45:00', 'ended_early', true],
      [0, '03:44:59', 'broken', false],
    ])(
      'D-08：延长 %i 分钟，%s 结束 → %s（F2 与 sync 一致）',
      async (extension, end, result, isQualified) => {
        const r = record(extension);
        const endedAt = new Date(`2026-08-01T${end}Z`);
        await driver.saveFastingRecord(r);
        const ended = await fasting.endFast(userId, randomUUID(), r.id, endedAt);
        expect(ended).toMatchObject({ result, isQualified });
        // 另一归属日新建，确保覆盖独立的 sync 判分入口。
        const synced = await push({
          ...payload(r),
          attributionDate: '2026-08-02',
          actualEndAt: endedAt.toISOString(),
        });
        expect(synced.results[0]).toMatchObject({
          status: 'applied',
          serverEntry: { result, isQualified },
        });
      },
    );

    it('sync 不允许通过 makeup 伪造窗口外达标，库存和达标集合不变', async () => {
      const before = await streak.getOrCreate(userId, TZ);
      const result = await push({ ...payload(), attributionDate: '2000-01-01', result: 'makeup' });
      expect(result.results[0]).toMatchObject({
        status: 'error',
        error: { code: 'VALIDATION_ERROR' },
      });
      expect(await driver.listFastingRecordsByUser(userId)).toHaveLength(0);
      expect((await streak.getOrCreate(userId, TZ)).makeupCards).toEqual(before.makeupCards);
    });

    it('已有服务端补签不被更晚的客户端 broken 覆写或删除', async () => {
      const date = addDays(localDateOf(new Date(), TZ), -1);
      await streak.makeUp(userId, randomUUID(), date, TZ);
      const marker = (await driver.listFastingRecordsByUser(userId))[0];
      const updated = await push({
        ...payload(),
        attributionDate: date,
        result: 'broken',
        actualEndAt: '2026-08-01T01:00:00Z',
        updatedAtUtc: '2099-01-01T00:00:00Z',
      });
      expect(updated.results[0]).toMatchObject({
        status: 'applied',
        serverEntry: { id: marker.id, result: 'makeup', isQualified: true },
      });
      const deleted = await sync.push(
        userId,
        [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'delete',
            serverId: marker.id,
          },
        ],
        TZ,
      );
      expect(deleted.results[0].status).toBe('error');
      expect(await driver.findFastingRecordById(marker.id)).toMatchObject({
        result: 'makeup',
        deletedAt: null,
        version: 1,
      });
      expect((await streak.getOrCreate(userId, TZ)).makeupCards.stock).toBe(1);
    });

    it('并发 PUT 方案只保留一条 current，GET 返回最后提交的方案', async () => {
      const completed: string[] = [];
      await Promise.all(
        ['16:8', '14:10'].map(async (type) => {
          const result = await fasting.putCurrentPlan(
            userId,
            TZ,
            type,
            type === '16:8' ? '12:00' : '10:00',
            '20:00',
          );
          completed.push(result.current.id);
        }),
      );
      const plans = await driver.listFastingPlansByUser(userId);
      expect(plans.filter((p) => p.status === 'current')).toHaveLength(1);
      expect((await fasting.getCurrentPlan(userId, TZ)).id).toBe(completed.at(-1));
    });

    it('方案新行写入失败时，旧 current 不会被提前过期', async () => {
      const previous = await fasting.putCurrentPlan(userId, TZ, '16:8', '12:00', '20:00');
      const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
      const save = prototype.saveFastingPlan;
      jest.spyOn(prototype, 'saveFastingPlan').mockImplementation(async function (
        this: StoreDriver,
        plan,
      ) {
        if (plan.status === 'current') throw new Error('plan write failed');
        return save.call(this, plan);
      });
      await expect(fasting.putCurrentPlan(userId, TZ, '14:10', '10:00', '20:00')).rejects.toThrow(
        'plan write failed',
      );
      expect(
        (await driver.listFastingPlansByUser(userId)).filter((p) => p.status === 'current'),
      ).toMatchObject([{ id: previous.current.id }]);
    });

    it('旧数据多个 current 与到期 pending 同时读取后只保留最新生效方案', async () => {
      const first = await fasting.putCurrentPlan(userId, TZ, '16:8', '12:00', '20:00');
      const base = (await driver.listFastingPlansByUser(userId))[0];
      const pendingId = randomUUID();
      await driver.saveFastingPlan({
        ...base,
        id: pendingId,
        planType: '14:10',
        status: 'pending',
        effectiveDate: '2000-01-01',
      });
      await driver.saveFastingPlan({
        ...base,
        id: randomUUID(),
        planType: '18:6',
        status: 'current',
      });
      await fasting.getCurrentPlan(userId, TZ);
      const current = (await driver.listFastingPlansByUser(userId)).filter(
        (p) => p.status === 'current',
      );
      expect(current).toHaveLength(1);
      expect(current[0].id).toBe(pendingId);
      expect(current[0].id).not.toBe(first.current.id);
    });

    async function candidateWithEntry() {
      const custom = (await food.createCustomFood(userId, {
        clientRequestId: randomUUID(),
        nameZh: '审核酸奶',
        per100g: { kcal: 60, proteinG: 3, carbG: 7, fatG: 2 },
        source: 'manual',
      })) as { id: string };
      foodIds.add(custom.id);
      const candidate = (await food.contributeCustomFood(userId, custom.id, {
        clientRequestId: randomUUID(),
      })) as { id: string };
      const entry = (await sync.createEntry(userId, {
        clientRequestId: randomUUID(),
        eatenAt: new Date().toISOString(),
        foodId: custom.id,
        grams: 100,
        inputMethod: 'manual',
      })) as { entry: { id: string } };
      return { foodId: custom.id, candidateId: candidate.id, entryId: entry.entry.id };
    }

    it('同时 approve/reject 只能一个终态成功，记录与终态保持一致', async () => {
      const { foodId, candidateId, entryId } = await candidateWithEntry();
      const reviews = await Promise.allSettled([
        food.reviewFoodCandidate(candidateId, { action: 'approve' }, 'admin-a'),
        food.reviewFoodCandidate(candidateId, { action: 'reject', reason: 'bad' }, 'admin-b'),
      ]);
      expect(reviews.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      const candidate = (await driver.findFoodCandidateById(candidateId))!;
      const entry = (await driver.findFoodEntryById(entryId))!;
      expect(!!(await driver.findFoodById(foodId))).toBe(candidate.status === 'approved');
      expect(!!entry.deletedAt).toBe(candidate.status === 'rejected');
    });

    it('审核落终态失败会回滚食物晋升，不留 pending 共享行', async () => {
      const { foodId, candidateId, entryId } = await candidateWithEntry();
      const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
      jest
        .spyOn(prototype, 'updateFoodCandidateStatus')
        .mockRejectedValueOnce(new Error('write failed'));
      await expect(food.reviewFoodCandidate(candidateId, { action: 'approve' })).rejects.toThrow(
        'write failed',
      );
      expect(await driver.findCustomFoodById(foodId)).not.toBeNull();
      expect(await driver.findFoodById(foodId)).toBeNull();
      expect(await driver.findFoodCandidateById(candidateId)).toMatchObject({ status: 'pending' });
      expect(await driver.findFoodEntryById(entryId)).toMatchObject({ deletedAt: null });
    });

    it('驳回级联写失败时回滚候选终态，保留原记录以便重试', async () => {
      const { candidateId, entryId } = await candidateWithEntry();
      const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
      jest
        .spyOn(prototype, 'softDeleteFoodEntriesByFood')
        .mockRejectedValueOnce(new Error('cascade failed'));
      await expect(
        food.reviewFoodCandidate(candidateId, { action: 'reject', reason: 'bad' }),
      ).rejects.toThrow('cascade failed');
      expect(await driver.findFoodCandidateById(candidateId)).toMatchObject({ status: 'pending' });
      expect(await driver.findFoodEntryById(entryId)).toMatchObject({ deletedAt: null });
    });

    it('纠错审核终态写失败时回滚营养修改', async () => {
      const { foodId, candidateId } = await candidateWithEntry();
      await food.reviewFoodCandidate(candidateId, { action: 'approve' });
      const correction = (await food.createFoodCorrection(userId, foodId, {
        clientRequestId: randomUUID(),
        per100g: { kcal: 80, proteinG: 4, carbG: 8, fatG: 3 },
      })) as { id: string };
      const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
      jest
        .spyOn(prototype, 'updateFoodCandidateStatus')
        .mockRejectedValueOnce(new Error('correction failed'));
      await expect(food.reviewFoodCandidate(correction.id, { action: 'approve' })).rejects.toThrow(
        'correction failed',
      );
      expect(await driver.findFoodById(foodId)).toMatchObject({ kcalPer100g: 60 });
      expect(await driver.findFoodCandidateById(correction.id)).toMatchObject({
        status: 'pending',
      });
    });

    it('删除食物与新增纠错并发，不会留下指向已删除食物的 pending 候选', async () => {
      const { foodId, candidateId } = await candidateWithEntry();
      await food.reviewFoodCandidate(candidateId, { action: 'approve' });
      const results = await Promise.allSettled([
        food.createFoodCorrection(userId, foodId, {
          clientRequestId: randomUUID(),
          per100g: { kcal: 80, proteinG: 4, carbG: 8, fatG: 3 },
        }),
        food.adminDeleteFood(foodId),
      ]);
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      const pending = (await driver.listFoodCandidates('pending')).filter(
        (c) => c.foodId === foodId,
      );
      if (pending.length > 0) expect(await driver.findFoodById(foodId)).not.toBeNull();
    });

    it('审核与删除候选并发后不会留下无候选的共享行或活记录', async () => {
      const { foodId, candidateId, entryId } = await candidateWithEntry();
      await Promise.allSettled([
        food.reviewFoodCandidate(candidateId, { action: 'approve' }),
        food.deleteFoodCandidate(candidateId),
      ]);
      expect(await driver.findFoodCandidateById(candidateId)).toBeNull();
      expect(await driver.findFoodById(foodId)).toBeNull();
      expect(await driver.findCustomFoodById(foodId)).toBeNull();
      expect((await driver.findFoodEntryById(entryId))?.deletedAt).not.toBeNull();
    });
  });
}

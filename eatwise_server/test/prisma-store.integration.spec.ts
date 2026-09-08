import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { FoodCandidateEntity, WaterLogEntity } from '../src/common/store/data-store';
import { PrismaStore } from '../src/common/store/prisma-store';
import { PrismaService } from '../src/infra/prisma.service';

/**
 * PrismaStore 集成测试：需要真实 PostgreSQL（docker compose up -d postgres +
 * npx prisma migrate deploy）。本机无 docker 时自动 skip（CI/本地起库后
 * `RUN_PG_TESTS=1 DATABASE_URL=... npm test` 执行）。
 */
const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;
const describePg = RUN_PG ? describe : describe.skip;

describePg('PrismaStore（集成，真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let userId: string;

  /** 导出/清除用例用最小饮水行（真实列由 createWaterLog 落库） */
  const waterLog = (): WaterLogEntity => {
    const now = new Date();
    return {
      id: randomUUID(),
      userId,
      clientRequestId: randomUUID(),
      amountMl: 250,
      loggedAt: new Date('2026-09-07T08:00:00Z'),
      localDate: '2026-09-07',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
  };
  const foodA = 'it-food-a';
  const foodB = 'it-food-b';

  beforeAll(async () => {
    prisma = new PrismaService(new ConfigService());
    await prisma.$connect();
    store = new PrismaStore(prisma);
    // 种子食物 + 测试用户
    await store.upsertFoods([
      {
        id: foodA,
        nameZh: '集成测试食物A',
        nameEn: 'IT Food A',
        aliases: [],
        kcalPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 10,
        fatPer100g: 5,
        category: '测试',
        source: 'cn_fct',
      },
      {
        id: foodB,
        nameZh: '集成测试食物B',
        nameEn: 'IT Food B',
        aliases: [],
        kcalPer100g: 200,
        proteinPer100g: 20,
        carbsPer100g: 0,
        fatPer100g: 10,
        category: '测试',
        source: 'usda',
      },
    ]);
    const user = await prisma.user.create({ data: { phone: '+86137TEST0001' } });
    userId = user.id;
  });

  afterAll(async () => {
    if (prisma) {
      await store.purgeUserData(userId).catch(() => undefined);
      await prisma.food.deleteMany({ where: { id: { in: [foodA, foodB] } } });
      await prisma.$disconnect();
    }
  });

  it('批量上行 ≤100/批：超限直接拒绝', async () => {
    const ops = Array.from({ length: 101 }, () => ({
      clientRequestId: randomUUID(),
      op: 'create' as const,
    }));
    await expect(store.pushFoodEntries(userId, ops)).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
  });

  it('create：事务落库 + 幂等重放返回首次结果 + 同键不同体报错', async () => {
    const crid = randomUUID();
    const op = {
      clientRequestId: crid,
      op: 'create' as const,
      payload: {
        eatenAt: new Date('2026-07-20T10:00:00Z').toISOString(),
        foodId: foodA,
        grams: 100,
      },
    };
    const [first] = await store.pushFoodEntries(userId, [op]);
    expect(first.status).toBe('applied');
    const entryId = (first.serverEntry as { id: string }).id;

    // 幂等重放：返回首次结果（同 serverEntry id）
    const [replay] = await store.pushFoodEntries(userId, [op]);
    expect(replay.status).toBe('applied');
    expect((replay.serverEntry as { id: string }).id).toBe(entryId);

    // 同键不同体 → IDEMPOTENCY_PAYLOAD_MISMATCH
    const [mismatch] = await store.pushFoodEntries(userId, [
      { ...op, payload: { ...op.payload, grams: 200 } },
    ]);
    expect(mismatch.status).toBe('error');
    expect(mismatch.errorCode).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
  });

  it('update/delete：LWW 版本冲突与 deleted_vs_modified', async () => {
    const crid = randomUUID();
    const [created] = await store.pushFoodEntries(userId, [
      {
        clientRequestId: crid,
        op: 'create',
        payload: { eatenAt: new Date().toISOString(), foodId: foodB, grams: 50 },
      },
    ]);
    const entry = created.serverEntry as { id: string; version: number };

    // baseVersion 不符 → version_mismatch
    const [stale] = await store.pushFoodEntries(userId, [
      {
        clientRequestId: randomUUID(),
        op: 'update',
        serverId: entry.id,
        baseVersion: 99,
        payload: { grams: 80 },
      },
    ]);
    expect(stale.status).toBe('conflict');
    expect(stale.conflictType).toBe('version_mismatch');

    // 正确版本 → applied，version+1
    const [updated] = await store.pushFoodEntries(userId, [
      {
        clientRequestId: randomUUID(),
        op: 'update',
        serverId: entry.id,
        baseVersion: entry.version,
        payload: { grams: 80 },
      },
    ]);
    expect(updated.status).toBe('applied');
    expect((updated.serverEntry as { version: number }).version).toBe(entry.version + 1);

    // 删除 → applied；再改 → deleted_vs_modified
    const [deleted] = await store.pushFoodEntries(userId, [
      { clientRequestId: randomUUID(), op: 'delete', serverId: entry.id },
    ]);
    expect(deleted.status).toBe('applied');
    const [afterDelete] = await store.pushFoodEntries(userId, [
      {
        clientRequestId: randomUUID(),
        op: 'update',
        serverId: entry.id,
        baseVersion: entry.version + 2,
        payload: { grams: 90 },
      },
    ]);
    expect(afterDelete.status).toBe('conflict');
    expect(afterDelete.conflictType).toBe('deleted_vs_modified');
  });

  it('U3 导出聚合 + U5 清除（物理删除 + 帖子匿名化）', async () => {
    await store.pushFoodEntries(userId, [
      {
        clientRequestId: randomUUID(),
        op: 'create',
        payload: { eatenAt: new Date().toISOString(), foodId: foodA, grams: 100 },
      },
    ]);
    await prisma.post.create({ data: { userId, text: '打卡', imageUrls: [] } });
    await store.createWaterLog(waterLog());

    const bundle = await store.collectUserExport(userId);
    expect(bundle).not.toBeNull();
    expect(bundle!.profile.id).toBe(userId);
    expect(bundle!.foodEntries.length).toBeGreaterThanOrEqual(1);
    expect(bundle!.posts).toHaveLength(1);
    expect(bundle!.waterLogs).toHaveLength(1);

    const report = await store.purgeUserData(userId);
    expect(report.foodEntries).toBeGreaterThanOrEqual(1);
    expect(report.postsAnonymized).toBe(1);
    expect(await prisma.user.findUnique({ where: { id: userId } })).toBeNull();
    // 饮水记录随账号物理清除（water_logs.userId 外键必填，未清则删用户行违反 FK）
    expect(await prisma.waterLog.count({ where: { userId } })).toBe(0);
    expect(await store.collectUserExport(userId)).toBeNull();
  });
});

/** 真实库缺口收口：饮水记录 / 食物候选审核 / 帖子举报计数（独立用户，逐条清表） */
describePg('PrismaStore 饮水 / 候选 / 举报（集成，真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let userId: string;

  const waterLog = (over: Partial<WaterLogEntity> = {}): WaterLogEntity => {
    const now = new Date();
    return {
      id: randomUUID(),
      userId,
      clientRequestId: randomUUID(),
      amountMl: 250,
      loggedAt: new Date('2026-09-07T08:00:00Z'),
      localDate: '2026-09-07',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      ...over,
    };
  };
  const candidate = (over: Partial<FoodCandidateEntity> = {}): FoodCandidateEntity => {
    const now = new Date();
    return {
      id: `fc_${randomUUID().slice(0, 8)}`,
      foodId: `custom_${randomUUID().slice(0, 8)}`,
      userId,
      status: 'pending',
      reason: null,
      clientRequestId: randomUUID(),
      version: 1,
      createdAt: now,
      updatedAt: now,
      ...over,
    };
  };

  beforeAll(async () => {
    prisma = new PrismaService(new ConfigService());
    await prisma.$connect();
    store = new PrismaStore(prisma);
    const user = await prisma.user.create({ data: { phone: '+86137TEST0002' } });
    userId = user.id;
  });

  beforeEach(async () => {
    await prisma.waterLog.deleteMany({ where: { userId } });
    await prisma.foodCandidate.deleteMany({ where: { userId } });
    await prisma.post.deleteMany({ where: { userId } });
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.waterLog.deleteMany({ where: { userId } });
      await prisma.foodCandidate.deleteMany({ where: { userId } });
      await prisma.user.deleteMany({ where: { id: userId } }).catch(() => undefined);
      await prisma.$disconnect();
    }
  });

  it('饮水：创建落库 + 按归属日查询（升序，排除 tombstone）', async () => {
    await store.createWaterLog(waterLog({ amountMl: 200, loggedAt: new Date('2026-09-07T09:00:00Z') }));
    await store.createWaterLog(waterLog({ amountMl: 300, loggedAt: new Date('2026-09-07T07:30:00Z') }));
    await store.createWaterLog(waterLog({ localDate: '2026-09-06' }));

    const rows = await store.findWaterLogsByUserAndDate(userId, '2026-09-07');
    expect(rows.map((r) => r.amountMl)).toEqual([300, 200]);
    expect(rows.every((r) => r.localDate === '2026-09-07')).toBe(true);
  });

  it('饮水：clientRequestId 幂等重放静默；软删留 tombstone；增量按 updatedAt', async () => {
    const first = waterLog({ clientRequestId: 'cr-water-1' });
    await store.createWaterLog(first);
    // 同键重放（不同 id）→ 静默成功，不产生第二行
    await store.createWaterLog(waterLog({ clientRequestId: 'cr-water-1', amountMl: 999 }));
    expect(await prisma.waterLog.count({ where: { userId } })).toBe(1);

    const since = new Date(Date.now() - 60_000);
    await store.deleteWaterLog(userId, 'cr-water-1');
    // 当日视图排除 tombstone
    expect(await store.findWaterLogsByUserAndDate(userId, '2026-09-07')).toHaveLength(0);
    // syncToken 增量：tombstone 仍下发（客户端据此删本地行）
    const changed = await store.findWaterLogsSince(userId, since);
    expect(changed).toHaveLength(1);
    expect(changed[0].id).toBe(first.id);
    expect(changed[0].deletedAt).not.toBeNull();
    expect(changed[0].version).toBe(2);
    // 未来游标 → 无增量
    expect(await store.findWaterLogsSince(userId, new Date(Date.now() + 60_000))).toHaveLength(0);
    // 重复删除幂等静默
    await expect(store.deleteWaterLog(userId, 'cr-water-1')).resolves.toBeUndefined();
    await expect(store.deleteWaterLog(userId, 'cr-missing')).resolves.toBeUndefined();
  });

  it('候选：提交落库 + 幂等键查重 + 审核状态/原因落库', async () => {
    const c = candidate({ clientRequestId: 'cr-cand-1' });
    await store.createFoodCandidate(c);

    const found = await store.findFoodCandidateByUserAndRequestId(userId, 'cr-cand-1');
    expect(found).not.toBeNull();
    expect(found!.id).toBe(c.id);
    expect(found!.foodId).toBe(c.foodId);
    expect(found!.status).toBe('pending');
    expect(await store.findFoodCandidateByUserAndRequestId(userId, 'cr-none')).toBeNull();

    // 同幂等键重放 → 静默，不产生第二条候选
    await store.createFoodCandidate(candidate({ clientRequestId: 'cr-cand-1' }));
    expect(await prisma.foodCandidate.count({ where: { userId } })).toBe(1);

    await store.updateFoodCandidateStatus(c.id, 'rejected', '  名称不规范  ');
    const row = await prisma.foodCandidate.findUnique({ where: { id: c.id } });
    expect(row!.status).toBe('rejected');
    expect(row!.reason).toBe('名称不规范'); // trim 后入库
    expect(row!.version).toBe(2);

    await store.updateFoodCandidateStatus(c.id, 'approved');
    expect((await prisma.foodCandidate.findUnique({ where: { id: c.id } }))!.status).toBe(
      'approved',
    );
    await expect(store.updateFoodCandidateStatus('fc_missing', 'approved')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
  });

  it('举报：reportCount 累加 + reportedAt 刷新；未知帖子 NOT_FOUND', async () => {
    const post = await prisma.post.create({ data: { userId, text: '打卡', imageUrls: [] } });
    expect(post.reportCount).toBe(0);
    expect(post.reportedAt).toBeNull();

    await store.incrementPostReportCount(post.id);
    const once = await prisma.post.findUnique({ where: { id: post.id } });
    expect(once!.reportCount).toBe(1);
    expect(once!.reportedAt).toBeInstanceOf(Date);

    await store.incrementPostReportCount(post.id);
    const twice = await prisma.post.findUnique({ where: { id: post.id } });
    expect(twice!.reportCount).toBe(2);
    expect(twice!.reportedAt!.getTime()).toBeGreaterThanOrEqual(once!.reportedAt!.getTime());

    // 实体映射读取真实列（不再是缺省 0/null）
    const bundle = await store.collectUserExport(userId);
    expect(bundle!.posts[0].reportCount).toBe(2);
    expect(bundle!.posts[0].reportedAt).toBeInstanceOf(Date);

    await expect(store.incrementPostReportCount('post_missing')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
  });
});

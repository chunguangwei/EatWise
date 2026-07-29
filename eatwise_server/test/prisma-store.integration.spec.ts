import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
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

    const bundle = await store.collectUserExport(userId);
    expect(bundle).not.toBeNull();
    expect(bundle!.profile.id).toBe(userId);
    expect(bundle!.foodEntries.length).toBeGreaterThanOrEqual(1);
    expect(bundle!.posts).toHaveLength(1);

    const report = await store.purgeUserData(userId);
    expect(report.foodEntries).toBeGreaterThanOrEqual(1);
    expect(report.postsAnonymized).toBe(1);
    expect(await prisma.user.findUnique({ where: { id: userId } })).toBeNull();
    expect(await store.collectUserExport(userId)).toBeNull();
  });
});

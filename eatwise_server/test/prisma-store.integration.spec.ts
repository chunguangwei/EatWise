import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import {
  CustomFoodEntity,
  FastingPlanEntity,
  FastingRecordEntity,
  FoodCandidateEntity,
  FoodEntryEntity,
  IdempotencyRecord,
  PostEntity,
  RefreshTokenEntity,
  StreakEntity,
  WaterLogEntity,
  ExerciseLogEntity,
  WeightLogEntity,
} from '../src/common/store/data-store';
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

  it('create：业务校验错误保留原 code（未知 foodId → VALIDATION_ERROR，不吞成 INTERNAL_ERROR）', async () => {
    const [res] = await store.pushFoodEntries(userId, [
      {
        clientRequestId: randomUUID(),
        op: 'create' as const,
        payload: {
          eatenAt: new Date('2026-07-20T10:00:00Z').toISOString(),
          foodId: 'no-such-food',
          grams: 100,
        },
      },
    ]);
    expect(res.status).toBe('error');
    expect(res.errorCode).toBe('VALIDATION_ERROR');
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

  it('listUsers：keyword 三字段不敏感匹配 + 排除 tombstone + 最新在前', async () => {
    const tag = randomUUID().slice(0, 8);
    const u3phone = `+8613900${String(parseInt(tag, 16) % 1_000_000).padStart(6, '0')}`;
    const [u1, u2, u3, gone] = await Promise.all([
      prisma.user.create({
        data: { username: `itlu-${tag}-a`, createdAt: new Date('2026-09-01T00:00:00Z') },
      }),
      prisma.user.create({
        data: { nickname: `ITLU ${tag} 昵称`, createdAt: new Date('2026-09-02T00:00:00Z') },
      }),
      prisma.user.create({
        data: { phone: u3phone, createdAt: new Date('2026-09-03T00:00:00Z') },
      }),
      prisma.user.create({
        data: {
          username: `itlu-${tag}-gone`,
          deletedAt: new Date(),
          createdAt: new Date('2026-09-04T00:00:00Z'),
        },
      }),
    ]);
    const ids = [u1.id, u2.id, u3.id, gone.id];
    try {
      // 全量（排除 tombstone）：u3/u2/u1 最新在前，gone 不出现
      const all = await store.listUsers();
      const mine = all.filter((u) => ids.includes(u.id));
      expect(mine.map((u) => u.id)).toEqual([u3.id, u2.id, u1.id]);

      // username 匹配（大小写不敏感）
      expect((await store.listUsers(`ITLU-${tag}-A`)).map((u) => u.id)).toEqual([u1.id]);
      // nickname 匹配（大小写不敏感）
      expect((await store.listUsers(`itlu ${tag}`)).map((u) => u.id)).toEqual([u2.id]);
      // phone 匹配
      expect((await store.listUsers(u3.phone!.slice(-6))).map((u) => u.id)).toEqual([u3.id]);
      // 无命中
      expect(await store.listUsers(`zzz-${tag}-zzz`)).toHaveLength(0);
    } finally {
      await prisma.user.deleteMany({ where: { id: { in: ids } } });
    }
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
    // 运动记录（2026-09-19 拍板上行：U3 导出含 exerciseLogs，U5 随账号清除）
    const now = new Date();
    const exercise: ExerciseLogEntity = {
      id: randomUUID(),
      userId,
      clientRequestId: randomUUID(),
      typeKey: 'walk',
      durationMin: 0,
      kcal: 68,
      steps: 1466,
      source: 'screenshot',
      loggedAt: now,
      localDate: '2026-09-19',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    await store.createExerciseLog(exercise);
    // 个人自定义食物 + 贡献候选（U5 需一并清除）
    const customFood: CustomFoodEntity = {
      id: `cf_${randomUUID().slice(0, 8)}`,
      userId,
      clientRequestId: randomUUID(),
      nameZh: '集成测试自定义食物',
      nameEn: 'IT Custom Food',
      aliases: [],
      kcalPer100g: 100,
      proteinPer100g: 10,
      carbsPer100g: 10,
      fatPer100g: 5,
      source: 'manual',
      createdAt: new Date(),
    };
    await store.createCustomFood(customFood);
    const candidate: FoodCandidateEntity = {
      id: `fc_${randomUUID().slice(0, 8)}`,
      foodId: customFood.id,
      userId,
      status: 'pending',
      reason: null,
      kind: 'custom',
      barcode: null,
      evidenceImageUrl: null,
      suggestion: null,
      reviewedBy: null,
      clientRequestId: randomUUID(),
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await store.createFoodCandidate(candidate);

    const bundle = await store.collectUserExport(userId);
    expect(bundle).not.toBeNull();
    expect(bundle!.profile.id).toBe(userId);
    expect(bundle!.foodEntries.length).toBeGreaterThanOrEqual(1);
    expect(bundle!.posts).toHaveLength(1);
    expect(bundle!.waterLogs).toHaveLength(1);
    expect(bundle!.exerciseLogs).toHaveLength(1);

    const report = await store.purgeUserData(userId);
    expect(report.foodEntries).toBeGreaterThanOrEqual(1);
    expect(report.postsAnonymized).toBe(1);
    expect(await prisma.user.findUnique({ where: { id: userId } })).toBeNull();
    // 饮水记录随账号物理清除（water_logs.userId 外键必填，未清则删用户行违反 FK）
    expect(await prisma.waterLog.count({ where: { userId } })).toBe(0);
    // 运动记录随账号物理清除（exercise_logs.userId 外键必填，同口径）
    expect(await prisma.exerciseLog.count({ where: { userId } })).toBe(0);
    // 个人自定义食物与贡献候选随账号清除
    expect(await prisma.food.count({ where: { createdByUserId: userId, isCustom: true } })).toBe(0);
    expect(await prisma.foodCandidate.count({ where: { userId } })).toBe(0);
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
  const exerciseLog = (over: Partial<ExerciseLogEntity> = {}): ExerciseLogEntity => {
    const now = new Date();
    return {
      id: randomUUID(),
      userId,
      clientRequestId: randomUUID(),
      typeKey: 'jog',
      durationMin: 30,
      kcal: 210,
      steps: null,
      source: null,
      loggedAt: new Date('2026-09-19T02:00:00Z'),
      localDate: '2026-09-19',
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
      kind: 'custom',
      barcode: null,
      evidenceImageUrl: null,
      suggestion: null,
      reviewedBy: null,
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
    await prisma.exerciseLog.deleteMany({ where: { userId } });
    await prisma.foodCandidate.deleteMany({ where: { userId } });
    await prisma.post.deleteMany({ where: { userId } });
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.waterLog.deleteMany({ where: { userId } });
      await prisma.exerciseLog.deleteMany({ where: { userId } });
      await prisma.foodCandidate.deleteMany({ where: { userId } });
      await prisma.user.deleteMany({ where: { id: userId } }).catch(() => undefined);
      await prisma.$disconnect();
    }
  });

  it('运动：clientRequestId 幂等重放静默；软删留 tombstone；增量按 updatedAt（含 steps/source 列）', async () => {
    const first = exerciseLog({ clientRequestId: 'cr-ex-1', steps: 1466, source: 'screenshot' });
    await store.createExerciseLog(first);
    // 同键重放（不同 id）→ 静默成功，不产生第二行
    await store.createExerciseLog(exerciseLog({ clientRequestId: 'cr-ex-1', kcal: 999 }));
    expect(await prisma.exerciseLog.count({ where: { userId } })).toBe(1);

    const since = new Date(Date.now() - 60_000);
    await store.deleteExerciseLog(userId, 'cr-ex-1');
    // syncToken 增量：tombstone 仍下发（客户端据此删本地行），字段完整回读
    const changed = await store.findExerciseLogsSince(userId, since);
    expect(changed).toHaveLength(1);
    expect(changed[0].id).toBe(first.id);
    expect(changed[0].deletedAt).not.toBeNull();
    expect(changed[0].steps).toBe(1466);
    expect(changed[0].source).toBe('screenshot');
  });

  it('饮水：创建落库 + 按归属日查询（升序，排除 tombstone）', async () => {
    await store.createWaterLog(
      waterLog({ amountMl: 200, loggedAt: new Date('2026-09-07T09:00:00Z') }),
    );
    await store.createWaterLog(
      waterLog({ amountMl: 300, loggedAt: new Date('2026-09-07T07:30:00Z') }),
    );
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

/** StoreDriver 全量 CRUD 基座：用户/令牌/断食/食物/饮食记录/Streak/幂等/帖子/点赞举报/队列/管理员 */
describePg('PrismaStore 全量 CRUD 基座（集成，真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let userId: string;

  const foodC = 'it-food-c';

  beforeAll(async () => {
    prisma = new PrismaService(new ConfigService());
    await prisma.$connect();
    store = new PrismaStore(prisma);
    await store.upsertFoods([
      {
        id: foodC,
        nameZh: '集成测试食物C',
        nameEn: 'IT Food C',
        aliases: [],
        kcalPer100g: 50,
        proteinPer100g: 5,
        carbsPer100g: 5,
        fatPer100g: 1,
        category: '测试',
        source: 'cn_fct',
      },
    ]);
    const user = await prisma.user.create({ data: { phone: '+86137TEST0003' } });
    userId = user.id;
  });

  beforeEach(async () => {
    const posts = await prisma.post.findMany({ where: { userId }, select: { id: true } });
    const postIds = posts.map((p) => p.id);
    await prisma.moderationQueue.deleteMany({ where: { postId: { in: postIds } } });
    await prisma.post.deleteMany({ where: { userId } }); // 级联清 likes/reports/queue
    await prisma.foodEntry.deleteMany({ where: { userId } });
    await prisma.fastingPlan.deleteMany({ where: { userId } });
    await prisma.fastingRecord.deleteMany({ where: { userId } });
    await prisma.streak.deleteMany({ where: { userId } });
    await prisma.idempotencyKey.deleteMany({ where: { userId } });
    await prisma.refreshToken.deleteMany({ where: { userId } });
    await prisma.food.deleteMany({ where: { createdByUserId: userId } });
  });

  afterAll(async () => {
    if (prisma) {
      await store.purgeUserData(userId).catch(() => undefined);
      await prisma.food.deleteMany({ where: { id: foodC } });
      await prisma.$disconnect();
    }
  });

  it('用户：创建缺省值 + 手机号/用户名（小写归一化，软删占位）+ 资料/删除状态 LWW', async () => {
    const created = await store.createUser({
      username: 'CrudUser',
      nickname: '小测',
      heightCm: 170,
    });
    expect(created.locale).toBe('zh-CN');
    expect(created.timezone).toBe('Asia/Shanghai');
    expect(created.version).toBe(1);
    expect(created.username).toBe('CrudUser');

    expect((await store.findUserByUsername('  cruduser '))!.id).toBe(created.id);
    expect(await store.findUserByUsername('nobody')).toBeNull();

    // 资料 LWW：仅更新给定字段，version+1
    const patched = await store.updateUserProfile(created.id, { weightKg: 65.5, goal: 'fat_loss' });
    expect(patched.weightKg).toBe(65.5);
    expect(patched.nickname).toBe('小测'); // 未给字段不动
    expect(patched.version).toBe(2);
    expect(patched.updatedAt.getTime()).toBeGreaterThanOrEqual(created.updatedAt.getTime());

    // D-21 settingsPrefs：JSON 包真实落库并回读
    const prefs = { locale: 'zh-CN', theme: 'dark', syncedAt: '2026-09-18T08:00:00.000Z' };
    const prefsPatched = await store.updateUserProfile(created.id, { settingsPrefs: prefs });
    expect(prefsPatched.settingsPrefs).toEqual(prefs);
    const reloaded = await store.findUserById(created.id);
    expect(reloaded!.settingsPrefs).toEqual(prefs);

    // 软删后：findUserById 原始读取仍在（调用方自判），findUserByUsername 仍占位，
    // updateUserProfile/updateUserDeletion → NOT_FOUND
    await prisma.user.update({ where: { id: created.id }, data: { deletedAt: new Date() } });
    expect((await store.findUserById(created.id))!.deletedAt).not.toBeNull();
    expect((await store.findUserByUsername('cruduser'))!.id).toBe(created.id);
    await expect(store.updateUserProfile(created.id, { goal: 'trial' })).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    await expect(store.updateUserDeletion(created.id, null, null)).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    await prisma.user.deleteMany({ where: { id: created.id } }); // 唯一占位释放
  });

  it('用户：删除状态机与手机号查找（排除软删）', async () => {
    const u = await store.createUser({ phone: '+86137CRUD001' });
    expect((await store.findUserByPhone('+86137CRUD001'))!.id).toBe(u.id);

    const pending = await store.updateUserDeletion(
      u.id,
      'pending',
      new Date('2026-09-15T00:00:00Z'),
    );
    expect(pending.deletionStatus).toBe('pending');
    expect(pending.scheduledDeletionAt).toEqual(new Date('2026-09-15T00:00:00Z'));
    const cleared = await store.updateUserDeletion(u.id, null, null);
    expect(cleared.deletionStatus).toBeNull();
    expect(cleared.version).toBe(pending.version + 1);

    await prisma.user.update({ where: { id: u.id }, data: { deletedAt: new Date() } });
    expect(await store.findUserByPhone('+86137CRUD001')).toBeNull();
    expect(await store.findUserById('user_missing')).toBeNull();
    await prisma.user.deleteMany({ where: { id: u.id } });
  });

  it('会话令牌：创建/按哈希查/活跃升序/吊销（幂等）/按设备吊销计数', async () => {
    const mk = (hash: string, over: Partial<RefreshTokenEntity> = {}): RefreshTokenEntity => ({
      id: randomUUID(),
      userId,
      tokenHash: hash,
      deviceId: 'dev-1',
      expiresAt: new Date(Date.now() + 3600_000),
      revokedAt: null,
      replacedBy: null,
      createdAt: new Date(),
      ...over,
    });
    await store.createRefreshToken(
      mk('rt-hash-1', { createdAt: new Date('2026-09-01T00:00:00Z') }),
    );
    await store.createRefreshToken(
      mk('rt-hash-2', { createdAt: new Date('2026-09-02T00:00:00Z') }),
    );
    await store.createRefreshToken(
      mk('rt-hash-3', { deviceId: 'dev-2', expiresAt: new Date(Date.now() - 1000) }), // 已过期
    );
    await store.createRefreshToken(
      mk('rt-hash-4', { deviceId: 'dev-2', revokedAt: new Date() }), // 已吊销
    );

    expect((await store.findRefreshTokenByHash('rt-hash-1'))!.userId).toBe(userId);
    expect(await store.findRefreshTokenByHash('rt-missing')).toBeNull();

    const active = await store.listActiveRefreshTokens(userId);
    expect(active.map((t) => t.tokenHash)).toEqual(['rt-hash-1', 'rt-hash-2']); // 升序，排除过期/吊销

    await store.revokeRefreshToken('rt-hash-1');
    await store.revokeRefreshToken('rt-hash-1'); // 重复吊销幂等
    expect((await store.findRefreshTokenByHash('rt-hash-1'))!.revokedAt).not.toBeNull();

    // 吊销口径同内存 logout：未吊销即匹配（不过滤过期），deviceId 过滤
    expect(await store.revokeUserRefreshTokens(userId, 'dev-2')).toBe(1); // rt-hash-3（已过期未吊销）
    expect(await store.revokeUserRefreshTokens(userId)).toBe(1); // 吊销 rt-hash-2
    expect(await store.listActiveRefreshTokens(userId)).toHaveLength(0);
  });

  it('断食方案/记录：upsert 往返 + eventLog JSON + 计划结束时刻定位', async () => {
    const plan: FastingPlanEntity = {
      id: `plan_${randomUUID().slice(0, 8)}`,
      userId,
      planType: '16:8',
      eatingWindowStart: '12:00',
      eatingWindowEnd: '20:00',
      effectiveDate: '2026-09-09',
      status: 'pending',
      clientRequestId: null,
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await store.saveFastingPlan(plan);
    plan.status = 'current';
    plan.version = 2;
    await store.saveFastingPlan(plan); // 整体替换
    const plans = await store.listFastingPlansByUser(userId);
    expect(plans).toHaveLength(1);
    expect(plans[0].status).toBe('current');

    const endAt = new Date('2026-09-09T04:00:00Z');
    const record: FastingRecordEntity = {
      id: `rec_${randomUUID().slice(0, 8)}`,
      userId,
      attributionDate: '2026-09-09',
      plannedStartAt: new Date('2026-09-08T12:00:00Z'),
      plannedEndAt: endAt,
      actualStartAt: null,
      actualEndAt: null,
      extendedMinutes: 0,
      fastedMinutes: null,
      result: 'on_track',
      isQualified: false,
      eventLog: [{ at: '2026-09-08T12:00:00Z', event: 'started' }],
      clientRequestId: null,
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    await store.saveFastingRecord(record);
    record.eventLog.push({
      at: '2026-09-08T13:00:00Z',
      event: 'extended',
      detail: { minutes: 30 },
    });
    record.extendedMinutes = 30;
    record.version = 2;
    await store.saveFastingRecord(record); // eventLog 全量回写

    const byEnd = await store.findFastingRecordByPlannedEnd(userId, endAt);
    expect(byEnd!.id).toBe(record.id);
    expect(byEnd!.eventLog).toHaveLength(2);
    expect(byEnd!.eventLog[1].detail).toEqual({ minutes: 30 });
    expect(
      await store.findFastingRecordByPlannedEnd(userId, new Date('2027-01-01T00:00:00Z')),
    ).toBeNull();
    expect((await store.findFastingRecordById(record.id))!.extendedMinutes).toBe(30);
    expect(await store.listFastingRecordsByUser(userId)).toHaveLength(1);
  });

  it('食物：内置按 id 读（排除自定义）+ 自定义 CRUD 往返', async () => {
    expect((await store.findFoodById(foodC))!.nameZh).toBe('集成测试食物C');
    expect(await store.findFoodById('food_missing')).toBeNull();

    const custom: CustomFoodEntity = {
      id: `cf_${randomUUID().slice(0, 8)}`,
      userId,
      clientRequestId: 'cr-custom-1',
      nameZh: '自定义测试',
      nameEn: 'Custom Test',
      aliases: ['custom'],
      kcalPer100g: 10,
      proteinPer100g: 1,
      carbsPer100g: 1,
      fatPer100g: 0.5,
      source: 'manual',
      createdAt: new Date(),
    };
    await store.createCustomFood(custom);
    // 内置视图不返回自定义行
    expect(await store.findFoodById(custom.id)).toBeNull();
    const found = await store.findCustomFoodById(custom.id);
    expect(found).toEqual(custom); // 含 clientRequestId 往返
    expect(await store.findCustomFoodsByUser(userId)).toHaveLength(1);

    await store.deleteCustomFood(custom.id);
    expect(await store.findCustomFoodById(custom.id)).toBeNull();
    expect(await store.findCustomFoodsByUser(userId)).toHaveLength(0);
  });

  it('饮食记录：upsert 往返 + 幂等键定位 + (updatedAt, id) 升序', async () => {
    const mk = (id: string, crid: string, kcal: number): FoodEntryEntity => ({
      id,
      userId,
      clientRequestId: crid,
      eatenAt: new Date('2026-09-08T08:00:00Z'),
      foodId: foodC,
      grams: 100,
      inputMethod: 'manual',
      photoUrl: null,
      nutritionSnapshot: { kcal, proteinG: 5, carbsG: 5, fatG: 1 },
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    });
    const a = mk(`fe_${randomUUID().slice(0, 8)}`, 'cr-entry-1', 50);
    const b = mk(`fe_${randomUUID().slice(0, 8)}`, 'cr-entry-2', 60);
    b.updatedAt = new Date(a.updatedAt.getTime() + 1000);
    await store.saveFoodEntry(b); // 先落 updatedAt 较晚的
    await store.saveFoodEntry(a);

    a.grams = 150;
    a.nutritionSnapshot = { kcal: 75, proteinG: 7.5, carbsG: 7.5, fatG: 1.5 };
    a.version = 2;
    a.updatedAt = new Date(b.updatedAt.getTime() + 1000);
    await store.saveFoodEntry(a); // 更新后置为最新

    expect((await store.findFoodEntryByClientRequestId(userId, 'cr-entry-1'))!.grams).toBe(150);
    expect(await store.findFoodEntryByClientRequestId(userId, 'cr-none')).toBeNull();
    const all = await store.listFoodEntriesByUser(userId);
    expect(all.map((e) => e.id)).toEqual([b.id, a.id]); // updatedAt 升序
    expect(all.every((e) => e.userId === userId)).toBe(true);
  });

  it('Streak：按 userId upsert（不存在则建、存在则整体覆盖）', async () => {
    expect(await store.findStreakByUser(userId)).toBeNull();
    const streak: StreakEntity = {
      id: `st_${randomUUID().slice(0, 8)}`,
      userId,
      currentStreak: 3,
      longestStreak: 3,
      lastQualifiedDate: '2026-09-07',
      milestones: { 3: '2026-09-07T00:00:00Z' },
      makeupCards: { stock: 2, month: '2026-09', usedDates: [] },
      version: 2,
      updatedAt: new Date(),
    };
    await store.saveStreak(streak);
    streak.currentStreak = 4;
    streak.version = 3;
    await store.saveStreak(streak);
    const found = await store.findStreakByUser(userId);
    expect(found!.currentStreak).toBe(4);
    expect(found!.milestones).toEqual({ 3: '2026-09-07T00:00:00Z' });
    expect(found!.makeupCards.stock).toBe(2);
  });

  it('幂等表：键 (userId, endpoint, clientRequestId) 往返 + 覆盖写', async () => {
    const rec: IdempotencyRecord = {
      userId,
      clientRequestId: 'cr-idem-1',
      endpoint: 'fasting/end',
      payloadHash: 'h1',
      responseBody: { ok: 1 },
      createdAt: new Date(),
    };
    await store.saveIdempotencyRecord(rec);
    expect(await store.findIdempotencyRecord(userId, 'fasting/end', 'cr-idem-1')).toEqual(rec);
    expect(await store.findIdempotencyRecord(userId, 'fasting/extend', 'cr-idem-1')).toBeNull();

    await store.saveIdempotencyRecord({ ...rec, payloadHash: 'h2', responseBody: { ok: 2 } });
    const updated = await store.findIdempotencyRecord(userId, 'fasting/end', 'cr-idem-1');
    expect(updated!.payloadHash).toBe('h2');
    expect(updated!.responseBody).toEqual({ ok: 2 });
  });

  it('帖子：upsert 往返 + 打卡流可见性/倒序 + 管理端 reported 口径', async () => {
    const mkPost = (id: string, over: Partial<PostEntity> = {}): PostEntity => ({
      id,
      userId,
      clientRequestId: null,
      text: '打卡',
      imageUrls: [],
      streakDaysAtPost: 3,
      anonymous: false,
      avatarId: null,
      likeCount: 0,
      auditStatus: 'approved',
      auditReason: null,
      reportCount: 0,
      reportedAt: null,
      visibility: 'public',
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
      ...over,
    });
    const older = mkPost(`post_${randomUUID().slice(0, 8)}`, {
      createdAt: new Date('2026-09-07T08:00:00Z'),
    });
    const newer = mkPost(`post_${randomUUID().slice(0, 8)}`, {
      createdAt: new Date('2026-09-08T08:00:00Z'),
    });
    const mine = mkPost(`post_${randomUUID().slice(0, 8)}`, {
      createdAt: new Date('2026-09-09T08:00:00Z'),
      auditStatus: 'pending',
    });
    await store.savePost(older);
    await store.savePost(newer);
    await store.savePost(mine);
    newer.text = '编辑后';
    newer.version = 2;
    await store.savePost(newer); // upsert 更新

    expect((await store.findPostById(newer.id))!.text).toBe('编辑后');
    expect(await store.findPostById('post_missing')).toBeNull();

    const feed = await store.findFeedPosts(userId);
    // 倒序：mine(pending 本人可见) > newer > older
    expect(feed.map((p) => p.id)).toEqual([mine.id, newer.id, older.id]);

    // 他人视角：pending 不可见
    const strangerFeed = await store.findFeedPosts('user_stranger');
    expect(strangerFeed.map((p) => p.id)).toEqual([newer.id, older.id]);

    // 管理端口径（U5 匿名化留存帖跨用例存在，按本用例 id 过滤后校验顺序）
    const only = (ids: string[]) => ids.filter((id) => [mine.id, newer.id, older.id].includes(id));
    expect(only((await store.listPostsForAdmin('pending')).map((p) => p.id))).toEqual([mine.id]);
    expect(only((await store.listPostsForAdmin('approved')).map((p) => p.id))).toEqual([
      newer.id,
      older.id,
    ]);
    expect(only((await store.listPostsForAdmin('rejected')).map((p) => p.id))).toHaveLength(0);
    expect(only((await store.listPostsForAdmin('reported')).map((p) => p.id))).toHaveLength(0);
    expect((await store.listPostsForAdmin(undefined)).length).toBeGreaterThanOrEqual(3);

    // tombstone 排除
    older.deletedAt = new Date();
    older.version = 2;
    await store.savePost(older);
    expect((await store.findFeedPosts(userId)).map((p) => p.id)).toEqual([mine.id, newer.id]);
  });

  it('点赞/举报：幂等计数、取消下限、唯一冲突静默、has 判定', async () => {
    const post: PostEntity = {
      id: `post_${randomUUID().slice(0, 8)}`,
      userId,
      clientRequestId: null,
      text: '打卡',
      imageUrls: [],
      streakDaysAtPost: null,
      anonymous: false,
      avatarId: null,
      likeCount: 0,
      auditStatus: 'approved',
      auditReason: null,
      reportCount: 0,
      reportedAt: null,
      visibility: 'public',
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    };
    await store.savePost(post);

    await store.likePost(post.id, 'user_a');
    await store.likePost(post.id, 'user_a'); // 幂等：不重复计数
    await store.likePost(post.id, 'user_b');
    expect((await store.findPostById(post.id))!.likeCount).toBe(2);
    expect(await store.hasPostLike(post.id, 'user_a')).toBe(true);
    expect(await store.hasPostLike(post.id, 'user_c')).toBe(false);
    await expect(store.likePost('post_missing', 'user_a')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });

    await store.unlikePost(post.id, 'user_a');
    await store.unlikePost(post.id, 'user_a'); // 未点赞过：静默
    expect((await store.findPostById(post.id))!.likeCount).toBe(1);

    await store.createPostReport(post.id, 'user_a', '垃圾信息');
    await store.createPostReport(post.id, 'user_a', '重复举报'); // 唯一冲突：幂等静默
    expect(await store.hasPostReport(post.id, 'user_a')).toBe(true);
    expect(await prisma.postReport.count({ where: { postId: post.id } })).toBe(1);
    expect(await prisma.postReport.findFirst({ where: { postId: post.id } })).toMatchObject({
      reason: '垃圾信息',
      userId: 'user_a',
    });
  });

  it('审核队列：入队保序 + 按帖清出计数', async () => {
    const mkPost = (id: string): PostEntity => ({
      id,
      userId,
      clientRequestId: null,
      text: '打卡',
      imageUrls: [],
      streakDaysAtPost: null,
      anonymous: false,
      avatarId: null,
      likeCount: 0,
      auditStatus: 'pending',
      auditReason: null,
      reportCount: 0,
      reportedAt: null,
      visibility: 'public',
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    });
    const p1 = mkPost(`post_${randomUUID().slice(0, 8)}`);
    const p2 = mkPost(`post_${randomUUID().slice(0, 8)}`);
    await store.savePost(p1);
    await store.savePost(p2);

    await store.enqueueModerationItem({
      postId: p1.id,
      source: 'auto',
      reason: 'manual',
      createdAt: new Date('2026-09-08T01:00:00Z'),
    });
    await store.enqueueModerationItem({
      postId: p1.id,
      source: 'report',
      reason: '举报1',
      createdAt: new Date('2026-09-08T02:00:00Z'),
    });
    await store.enqueueModerationItem({
      postId: p2.id,
      source: 'auto',
      reason: 'manual',
      createdAt: new Date('2026-09-08T03:00:00Z'),
    });

    const queue = await store.listModerationQueue();
    expect(queue.map((q) => q.postId)).toEqual([p1.id, p1.id, p2.id]); // 入队顺序
    expect(queue[1]).toMatchObject({ source: 'report', reason: '举报1' });

    expect(await store.removeModerationByPost(p1.id)).toBe(2); // 同帖多条全清
    expect(await store.removeModerationByPost(p1.id)).toBe(0); // 幂等
    expect((await store.listModerationQueue()).map((q) => q.postId)).toEqual([p2.id]);
  });

  it('管理员账号：创建 + 用户名小写查 + 计数', async () => {
    const username = `Admin_${randomUUID().slice(0, 8)}`;
    const before = await store.countAdminUsers();
    const admin = await store.createAdminUser({
      username,
      passwordHash: 'hash-x',
      role: 'reviewer',
      disabled: false,
    });
    expect(admin.createdAt).toBeInstanceOf(Date);
    expect((await store.findAdminByUsername(username.toLowerCase()))!.id).toBe(admin.id);
    expect((await store.findAdminById(admin.id))!.role).toBe('reviewer');
    expect(await store.countAdminUsers()).toBe(before + 1);
    await prisma.adminUser.deleteMany({ where: { id: admin.id } });
  });

  it('U5 清除：点赞/举报幂等记录随账号物理删除', async () => {
    const post: PostEntity = {
      id: `post_${randomUUID().slice(0, 8)}`,
      userId,
      clientRequestId: null,
      text: '打卡',
      imageUrls: [],
      streakDaysAtPost: null,
      anonymous: false,
      avatarId: null,
      likeCount: 1,
      auditStatus: 'approved',
      auditReason: null,
      reportCount: 1,
      reportedAt: new Date(),
      visibility: 'public',
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    };
    await store.savePost(post);
    await store.likePost(post.id, userId);
    await store.createPostReport(post.id, userId, '自测');
    expect(await prisma.postLike.count({ where: { userId } })).toBe(1);
    expect(await prisma.postReport.count({ where: { userId } })).toBe(1);

    await store.purgeUserData(userId); // 匿名化帖子（保留）+ 清点赞/举报 + 删用户
    expect(await prisma.postLike.count({ where: { userId } })).toBe(0);
    expect(await prisma.postReport.count({ where: { userId } })).toBe(0);
    expect(await prisma.post.count({ where: { id: post.id } })).toBe(1); // 帖子匿名化留存
    expect(await prisma.user.findUnique({ where: { id: userId } })).toBeNull();

    const orphan = await prisma.post.findUnique({ where: { id: post.id } });
    expect(orphan!.userId).toBeNull(); // 匿名化口径：解除用户关联
    await prisma.post.deleteMany({ where: { id: post.id } }); // 测试痕迹清理
  });
});

/** StoreDriver 基座第二批：auth 轮换/改密 + K1 搜索 + 候选读路径 + 审核晋升（独立用户） */
describePg('PrismaStore auth / 食物搜索 / 候选 / 晋升（集成，真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let userId: string;
  let otherId: string;

  // 命中层级 + 可见性矩阵（'itsea' 为本用例独占词，避开 foods.seed.json 真实食物）
  const seeds = [
    { id: 'it-search-a', nameZh: '海鲜A前缀', nameEn: 'Itsea A', aliases: [] as string[] },
    { id: 'it-search-b', nameZh: '海鲜B前缀', nameEn: 'Itsea B', aliases: [] as string[] },
    { id: 'it-search-c', nameZh: '香海鲜串', nameEn: 'X Itsea', aliases: [] as string[] },
    { id: 'it-search-d', nameZh: '别名海鲜', nameEn: 'Uni D', aliases: ['itseashell'] },
  ];

  const candidate = (over: Partial<FoodCandidateEntity> = {}): FoodCandidateEntity => {
    const now = new Date();
    return {
      id: `fc_${randomUUID().slice(0, 8)}`,
      foodId: `cf_${randomUUID().slice(0, 8)}`,
      userId,
      status: 'pending',
      reason: null,
      kind: 'custom',
      barcode: null,
      evidenceImageUrl: null,
      suggestion: null,
      reviewedBy: null,
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
    const user = await prisma.user.create({ data: { phone: '+86137TEST0004' } });
    userId = user.id;
    const other = await prisma.user.create({ data: { phone: '+86137TEST0005' } });
    otherId = other.id;
    await store.upsertFoods(
      seeds.map((s) => ({
        id: s.id,
        nameZh: s.nameZh,
        nameEn: s.nameEn,
        aliases: s.aliases,
        kcalPer100g: 10,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 0,
        category: '测试',
        source: 'cn_fct',
      })),
    );
    // 自定义：本人 1 条 + 他人 1 条（可见性隔离）
    await prisma.food.createMany({
      data: [
        {
          id: 'it-search-mine',
          nameZh: '自海鲜前缀',
          nameEn: 'Itsea Mine',
          aliases: [],
          kcalPer100g: 10,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 0,
          category: '自定义',
          source: 'manual',
          isCustom: true,
          createdByUserId: userId,
        },
        {
          id: 'it-search-other',
          nameZh: '他海鲜前缀',
          nameEn: 'Itsea Other',
          aliases: [],
          kcalPer100g: 10,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 0,
          category: '自定义',
          source: 'manual',
          isCustom: true,
          createdByUserId: otherId,
        },
      ],
    });
  });

  beforeEach(async () => {
    await prisma.foodCandidate.deleteMany({ where: { userId } });
    await prisma.refreshToken.deleteMany({ where: { userId } });
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.foodCandidate.deleteMany({ where: { userId } });
      await prisma.food.deleteMany({
        where: { id: { in: [...seeds.map((s) => s.id), 'it-search-mine', 'it-search-other'] } },
      });
      await prisma.user.deleteMany({
        where: { id: { in: [userId, otherId] } },
      });
      await prisma.$disconnect();
    }
  });

  it('rotateRefreshToken：置 revokedAt + replacedBy；重复轮换幂等覆盖；未知哈希静默', async () => {
    const hash = `rot-${randomUUID().slice(0, 8)}`;
    const now = new Date();
    await store.createRefreshToken({
      id: randomUUID(),
      userId,
      tokenHash: hash,
      deviceId: 'dev-1',
      expiresAt: new Date(now.getTime() + 3600_000),
      revokedAt: null,
      replacedBy: null,
      createdAt: now,
    });

    await store.rotateRefreshToken(hash, 'hash-new-1');
    let row = await store.findRefreshTokenByHash(hash);
    expect(row!.revokedAt).toBeInstanceOf(Date);
    expect(row!.replacedBy).toBe('hash-new-1');
    // 已轮换旧值重放（Reuse Detection 链路）→ 幂等静默，不抛错
    await store.rotateRefreshToken(hash, 'hash-new-2');
    row = await store.findRefreshTokenByHash(hash);
    expect(row!.replacedBy).toBe('hash-new-2');
    await expect(store.rotateRefreshToken('hash-unknown', 'x')).resolves.toBeUndefined();
    expect(await store.listActiveRefreshTokens(userId)).toHaveLength(0); // 轮换后不再活跃
  });

  it('updateUserPasswordHash：哈希落库 + version 递增；已删/未知用户 NOT_FOUND', async () => {
    const u = await store.createUser({ username: `pwd_${randomUUID().slice(0, 8)}` });
    expect(u.passwordHash).toBeNull();

    const rotated = await store.updateUserPasswordHash(u.id, 'bcrypt-hash-1');
    expect(rotated.passwordHash).toBe('bcrypt-hash-1');
    expect(rotated.version).toBe(u.version + 1);

    const again = await store.updateUserPasswordHash(u.id, 'bcrypt-hash-2');
    expect(again.passwordHash).toBe('bcrypt-hash-2');
    expect(again.version).toBe(rotated.version + 1);

    await prisma.user.update({ where: { id: u.id }, data: { deletedAt: new Date() } });
    await expect(store.updateUserPasswordHash(u.id, 'x')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    await expect(store.updateUserPasswordHash('user_missing', 'x')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    await prisma.user.deleteMany({ where: { id: u.id } });
  });

  it('searchFoods：内置前缀(同分 nameZh 升序) > 子串 > 别名，本人自定义置后；他人自定义不可见 + limit', async () => {
    const hits = await store.searchFoods('itsea', userId);
    expect(hits.map((h) => h.food.id)).toEqual([
      'it-search-a', // score 3 同分 → nameZh 升序
      'it-search-b',
      'it-search-c', // score 2 子串
      'it-search-d', // score 1 别名
      'it-search-mine', // 本人自定义整体置后
    ]);
    expect(hits[0]).toMatchObject({ isCustom: false, score: 3, matchedOn: 'nameEn' });
    expect(hits[3]).toMatchObject({
      score: 1,
      matchedOn: 'alias',
      highlight: { text: 'itseashell' },
    });
    expect(hits[4]).toMatchObject({ isCustom: true, score: 3 });

    // 无 userId → 仅内置/共享（含他人/本人自定义均不可见）
    expect((await store.searchFoods('itsea')).map((h) => h.food.id)).toEqual([
      'it-search-a',
      'it-search-b',
      'it-search-c',
      'it-search-d',
    ]);
    // limit 截断 + 空/无命中查询
    expect((await store.searchFoods('itsea', userId, 'zh-CN', 2)).map((h) => h.food.id)).toEqual([
      'it-search-a',
      'it-search-b',
    ]);
    expect(await store.searchFoods('   ', userId)).toHaveLength(0);
    expect(await store.searchFoods('不存在词zzz', userId)).toHaveLength(0);
  });

  it('候选读路径：按 id / 按 foodId / 审核队列（status 过滤 + 先入先审）', async () => {
    const old = candidate({ status: 'approved', createdAt: new Date('2026-09-01T00:00:00Z') });
    const mid = candidate({ status: 'pending', createdAt: new Date('2026-09-02T00:00:00Z') });
    const late = candidate({ status: 'pending', createdAt: new Date('2026-09-03T00:00:00Z') });
    for (const c of [old, mid, late]) await store.createFoodCandidate(c);

    expect((await store.findFoodCandidateById(mid.id))!.foodId).toBe(mid.foodId);
    expect(await store.findFoodCandidateById('fc_missing')).toBeNull();

    // contribute 幂等定位：同一食物只允许一个候选
    expect((await store.findFoodCandidateByFoodId(mid.foodId))!.id).toBe(mid.id);
    expect(await store.findFoodCandidateByFoodId('cf_none')).toBeNull();

    const mineOnly = (rows: FoodCandidateEntity[]) =>
      rows.filter((c) => [old.id, mid.id, late.id].includes(c.id));
    expect(mineOnly(await store.listFoodCandidates('pending')).map((c) => c.id)).toEqual([
      mid.id,
      late.id,
    ]);
    expect(mineOnly(await store.listFoodCandidates()).map((c) => c.id)).toEqual([
      old.id,
      mid.id,
      late.id,
    ]);

    // 我的贡献：仅本人 + 最新在前（createdAt 降序 + id 降序）
    expect((await store.findFoodCandidatesByUser(userId)).map((c) => c.id)).toEqual([
      late.id,
      mid.id,
      old.id,
    ]);
    expect((await store.findFoodCandidatesByUser(userId, 'pending')).map((c) => c.id)).toEqual([
      late.id,
      mid.id,
    ]);
    expect(await store.findFoodCandidatesByUser(otherId)).toHaveLength(0);
    expect(await store.findFoodCandidatesByUser(userId, 'rejected')).toHaveLength(0);
  });

  it('条码候选：findFoodCandidateByBarcode 查重口径（pending 优先 / approved 次之 / rejected 不阻断）', async () => {
    const barcode = `itbc${randomUUID().slice(0, 8)}`;
    // 仅 rejected → 不阻断（返回 null，可重新提交）
    await store.createFoodCandidate(
      candidate({
        kind: 'barcode',
        barcode,
        evidenceImageUrl: '/v1/uploads/a.jpg',
        status: 'rejected',
      }),
    );
    expect(await store.findFoodCandidateByBarcode(barcode)).toBeNull();

    // approved 早、pending 晚 → 仍返回 pending（pending 优先于 approved）
    const approvedFirst = candidate({
      kind: 'barcode',
      barcode,
      evidenceImageUrl: '/v1/uploads/a.jpg',
      status: 'approved',
      createdAt: new Date('2026-09-01T00:00:00Z'),
    });
    const pendingLater = candidate({
      kind: 'barcode',
      barcode,
      evidenceImageUrl: '/v1/uploads/a.jpg',
      status: 'pending',
      createdAt: new Date('2026-09-02T00:00:00Z'),
    });
    await store.createFoodCandidate(approvedFirst);
    await store.createFoodCandidate(pendingLater);
    expect((await store.findFoodCandidateByBarcode(barcode))!.id).toBe(pendingLater.id);
    // 其他条码 / custom 候选（barcode=null）不命中
    expect(await store.findFoodCandidateByBarcode(`itbc-none`)).toBeNull();
  });

  it('promoteCustomFoodToShared 带 barcode：共享行写入 foods.barcode（扫码命中自有库）', async () => {
    const customId = `it-promote-bc-${randomUUID().slice(0, 8)}`;
    await prisma.food.create({
      data: {
        id: customId,
        nameZh: '条码晋升测试食品',
        nameEn: 'IT Barcode Promote',
        aliases: [],
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        category: '自定义',
        source: 'manual',
        isCustom: true,
        createdByUserId: userId,
      },
    });
    try {
      await store.promoteCustomFoodToShared(customId, '6901234567892');
      expect(await store.findFoodById(customId)).toMatchObject({
        id: customId,
        barcode: '6901234567892',
        source: 'community',
        category: '社区共享',
      });
      // findFoodByBarcode：共享行按条码命中（条码查询第一跳）
      expect((await store.findFoodByBarcode('6901234567892'))!.id).toBe(customId);
      expect(await store.findFoodByBarcode('6999999999999')).toBeNull();
    } finally {
      await prisma.food.deleteMany({ where: { id: customId } });
    }
    // 未晋升的自定义行（isCustom=true）即使带 barcode 也不命中共享口径
    const customOnlyId = `it-bc-custom-${randomUUID().slice(0, 8)}`;
    await prisma.food.create({
      data: {
        id: customOnlyId,
        nameZh: '未晋升条码食品',
        nameEn: 'IT Barcode Custom Only',
        aliases: [],
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        category: '自定义',
        source: 'manual',
        isCustom: true,
        createdByUserId: userId,
        barcode: '6901234567893',
      },
    });
    try {
      expect(await store.findFoodByBarcode('6901234567893')).toBeNull();
    } finally {
      await prisma.food.deleteMany({ where: { id: customOnlyId } });
    }
  });

  it('promoteCustomFoodToShared：id 不变转共享（个人库消失、共享库可见）；未知 id NOT_FOUND', async () => {
    expect((await store.findCustomFoodById('it-search-mine'))!.nameZh).toBe('自海鲜前缀');

    await store.promoteCustomFoodToShared('it-search-mine');

    expect(await store.findCustomFoodById('it-search-mine')).toBeNull();
    expect(await store.findCustomFoodsByUser(userId)).toHaveLength(0);
    expect(await store.findFoodById('it-search-mine')).toMatchObject({
      id: 'it-search-mine',
      nameZh: '自海鲜前缀',
      source: 'community',
      category: '社区共享',
      createdByUserId: userId, // 溯源保留；id 不变 → FoodEntry 引用不断链
    });
    // 晋升后立即进入内置/共享结果集（对任意用户可见）
    expect((await store.searchFoods('itsea')).map((h) => h.food.id)).toContain('it-search-mine');

    await expect(store.promoteCustomFoodToShared('food_missing')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    // 已是共享行（非自定义）→ 不重复晋升
    await expect(store.promoteCustomFoodToShared('it-search-mine')).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
  });

  it('纠错候选：suggestion JSON 往返 + applyFoodCorrection 应用建议值到共享行', async () => {
    const suggestion = {
      nameZh: '海鲜A前缀（修正）',
      nameEn: null,
      per100g: { kcal: 120, proteinG: 6, carbG: 8, fatG: 2 },
    };
    const c = candidate({ foodId: 'it-search-a', kind: 'correction', suggestion });
    await store.createFoodCandidate(c);

    // suggestion JSON 列往返（审核台原值 vs 建议值对照数据源）。
    const found = (await store.findFoodCandidateById(c.id))!;
    expect(found.kind).toBe('correction');
    expect(found.suggestion).toEqual(suggestion);

    // approve 路径：建议名 + 四营养应用到共享行；建议名 null 的字段不动。
    await store.applyFoodCorrection('it-search-a', found.suggestion!);
    expect(await store.findFoodById('it-search-a')).toMatchObject({
      nameZh: '海鲜A前缀（修正）',
      nameEn: 'Itsea A', // 建议 nameEn=null → 保持原值
      kcalPer100g: 120,
      proteinPer100g: 6,
      carbsPer100g: 8,
      fatPer100g: 2,
    });
    // 自定义行/不存在 → NOT_FOUND（与内存驱动同口径）。
    await expect(store.applyFoodCorrection('it-search-other', suggestion)).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    await prisma.foodCandidate.deleteMany({ where: { id: c.id } }); // 测试痕迹清理
  });
});

/** 阶段 C：体重记录真实库（独立用户，逐条清表） */
describePg('PrismaStore 体重记录（集成，真实 PostgreSQL）', () => {
  let prisma: PrismaService;
  let store: PrismaStore;
  let userId: string;

  const weightLog = (over: Partial<WeightLogEntity> = {}): WeightLogEntity => {
    const now = new Date();
    return {
      id: randomUUID(),
      userId,
      clientRequestId: randomUUID(),
      date: '2026-09-17',
      weightKg: 65.5,
      bodyFatPct: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      ...over,
    };
  };

  beforeAll(async () => {
    prisma = new PrismaService(new ConfigService());
    await prisma.$connect();
    store = new PrismaStore(prisma);
    const user = await prisma.user.create({ data: { phone: '+86137TEST0006' } });
    userId = user.id;
  });

  beforeEach(async () => {
    await prisma.weightLog.deleteMany({ where: { userId } });
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.weightLog.deleteMany({ where: { userId } });
      await prisma.user.deleteMany({ where: { id: userId } }).catch(() => undefined);
      await prisma.$disconnect();
    }
  });

  it('saveWeightLog：新建/同日覆写 upsert 往返 + 幂等键定位 + 软删 tombstone', async () => {
    const log = weightLog({ clientRequestId: 'cr-weight-1', bodyFatPct: 18.2 });
    await store.saveWeightLog(log);
    const found = await store.findWeightLogByClientRequestId(userId, 'cr-weight-1');
    expect(found).toMatchObject({ id: log.id, weightKg: 65.5, bodyFatPct: 18.2 });

    // 同日覆写（应用层 upsert 落库口径：同 id update，version+1）
    const updated: WeightLogEntity = {
      ...log,
      clientRequestId: 'cr-weight-2',
      weightKg: 64.9,
      bodyFatPct: null,
      version: 2,
      updatedAt: new Date(),
    };
    await store.saveWeightLog(updated);
    expect(await prisma.weightLog.count({ where: { userId } })).toBe(1);
    expect(await store.findWeightLogByClientRequestId(userId, 'cr-weight-1')).toBeNull();
    const after = await store.findWeightLogByUserAndDate(userId, '2026-09-17');
    expect(after).toMatchObject({ id: log.id, weightKg: 64.9, version: 2 });

    // 软删 tombstone：同日定位排除，按 id 仍在
    await store.saveWeightLog({ ...after!, deletedAt: new Date(), version: 3 });
    expect(await store.findWeightLogByUserAndDate(userId, '2026-09-17')).toBeNull();
    expect((await store.findWeightLogById(log.id))!.deletedAt).not.toBeNull();
  });

  it('区间查询：含端点、date 升序、排除 tombstone 与他用户', async () => {
    await store.saveWeightLog(weightLog({ date: '2026-09-03', weightKg: 66 }));
    await store.saveWeightLog(weightLog({ date: '2026-09-01', weightKg: 67 }));
    await store.saveWeightLog(weightLog({ date: '2026-09-02', weightKg: 66.5 }));
    await store.saveWeightLog(
      weightLog({ date: '2026-09-02', weightKg: 99, deletedAt: new Date() }),
    );

    const rows = await store.findWeightLogsByUserRange(userId, '2026-09-01', '2026-09-02');
    expect(rows.map((r) => `${r.date}:${r.weightKg}`)).toEqual([
      '2026-09-01:67',
      '2026-09-02:66.5',
    ]);
    expect(
      await store.findWeightLogsByUserRange('user_stranger', '2026-09-01', '2026-09-03'),
    ).toHaveLength(0);
  });

  it('U3 导出含体重记录；U5 清除随账号物理删除', async () => {
    await store.saveWeightLog(weightLog({ clientRequestId: 'cr-weight-export' }));
    const bundle = await store.collectUserExport(userId);
    expect(bundle!.weightLogs).toHaveLength(1);
    expect(bundle!.weightLogs![0].weightKg).toBe(65.5);

    await store.purgeUserData(userId);
    expect(await prisma.weightLog.count({ where: { userId } })).toBe(0);
    // purge 后用户行已删，重建供后续用例/清理（不影响其他 describe 的独立用户）
    const user = await prisma.user.create({ data: { id: userId, phone: '+86137TEST0006' } });
    expect(user.id).toBe(userId);
  });
});

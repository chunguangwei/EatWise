import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

const ADMIN = 'test-admin-token';

/**
 * e2e：众包食物审核池（食物库扩充第三层）
 * 贡献（幂等/所有权/机审三态）→ 管理端审核（token 保护/approve 晋升/reject 退回）→ 搜索可见性矩阵。
 */
describe('Food contribute & admin review (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
  });

  let seq = 0;
  function nextPhone(): string {
    seq += 1;
    return `+8613922${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-candidate', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  let uuidSeq = 0;
  function nextUuid(): string {
    uuidSeq += 1;
    return `b2c3d4e5-${String(uuidSeq).padStart(4, '0')}-4111-8111-111111111111`;
  }

  async function createCustom(token: string, nameZh: string): Promise<string> {
    const res = await request(server)
      .post('/v1/foods/custom')
      .set(auth(token))
      .send({
        clientRequestId: nextUuid(),
        nameZh,
        per100g: { kcal: 100, proteinG: 10, carbG: 10, fatG: 5 },
        source: 'manual',
      })
      .expect(200);
    return res.body.data.id as string;
  }

  async function searchIds(token: string, q: string): Promise<Array<Record<string, unknown>>> {
    const res = await request(server)
      .get(`/v1/foods/search?q=${encodeURIComponent(q)}`)
      .set(auth(token))
      .expect(200);
    return res.body.data.items as Array<Record<string, unknown>>;
  }

  describe('POST /v1/foods/custom/:id/contribute', () => {
    it('贡献成功 → 候选 pending；未审核前他人不可见、创建者仍按自定义可见', async () => {
      const owner = await login(nextPhone());
      const stranger = await login(nextPhone());
      const foodId = await createCustom(owner, '候选酱牛肉');

      const res = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      expect(res.body.data.foodId).toBe(foodId);
      expect(res.body.data.status).toBe('pending');
      expect(res.body.data.nameZh).toBe('候选酱牛肉');

      // pending：创建者仍可见（isCustom），他人不可见
      const mine = await searchIds(owner, '候选酱牛肉');
      const hit = mine.find((i) => i.id === foodId);
      expect(hit).toBeDefined();
      expect(hit?.isCustom).toBe(true);
      const theirs = await searchIds(stranger, '候选酱牛肉');
      expect(theirs.find((i) => i.id === foodId)).toBeUndefined();
    });

    it('幂等：同 clientRequestId 重放返回同一候选；换 clientRequestId 重复贡献返回原状态', async () => {
      const owner = await login(nextPhone());
      const foodId = await createCustom(owner, '幂等卤蛋');
      const reqId = nextUuid();

      const first = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: reqId })
        .expect(200);
      const replay = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: reqId })
        .expect(200);
      expect(replay.body.data.id).toBe(first.body.data.id);

      const again = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      expect(again.body.data.id).toBe(first.body.data.id);
      expect(again.body.data.status).toBe('pending');
    });

    it('同 clientRequestId 贡献不同食物 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
      const owner = await login(nextPhone());
      const foodA = await createCustom(owner, '幂等冲突甲');
      const foodB = await createCustom(owner, '幂等冲突乙');
      const reqId = nextUuid();
      await request(server)
        .post(`/v1/foods/custom/${foodA}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: reqId })
        .expect(200);
      const res = await request(server)
        .post(`/v1/foods/custom/${foodB}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: reqId })
        .expect(409);
      expect(res.body.error.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    });

    it('所有权：他人的自定义食物/不存在的 id → 404；未认证 → 401', async () => {
      const owner = await login(nextPhone());
      const stranger = await login(nextPhone());
      const foodId = await createCustom(owner, '私有炸酱面');

      await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(stranger))
        .send({ clientRequestId: nextUuid() })
        .expect(404);
      await request(server)
        .post('/v1/foods/custom/cf_notexist/contribute')
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(404);
      await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .send({ clientRequestId: nextUuid() })
        .expect(401);
    });

    it('机审 rejected（违规词）→ 400 FOOD_CONTRIBUTE_REJECTED（双语 reason）；manual（疑似词）→ 仍 pending', async () => {
      const owner = await login(nextPhone());
      const bad = await createCustom(owner, '赌博主题套餐');
      const res = await request(server)
        .post(`/v1/foods/custom/${bad}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(400);
      expect(res.body.error.code).toBe('FOOD_CONTRIBUTE_REJECTED');
      expect(res.body.error.message).toBe('食物名称未通过审核，无法贡献到共享食物库');
      expect(res.body.error.details.reason.zh).toBeTruthy();
      expect(res.body.error.details.reason.en).toBeTruthy();

      const en = await request(server)
        .post(`/v1/foods/custom/${bad}/contribute`)
        .set(auth(owner))
        .set('Accept-Language', 'en')
        .send({ clientRequestId: nextUuid() })
        .expect(400);
      expect(en.body.error.message).toBe(
        'Food name did not pass review and cannot be contributed to the shared food library',
      );

      const manual = await createCustom(owner, '代购奶粉冲调谷物');
      const pending = await request(server)
        .post(`/v1/foods/custom/${manual}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      expect(pending.body.data.status).toBe('pending');
    });
  });

  describe('条码商品贡献（带营养表佐证照片）', () => {
    it('全链路：提交 → 审核队列可见条码与佐证照片 → approve → 共享 Food 带 barcode', async () => {
      const owner = await login(nextPhone());
      const foodId = await createCustom(owner, '条码奥利奥');

      const submitted = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({
          clientRequestId: nextUuid(),
          barcode: '7622210449283',
          evidenceImageUrl: '/v1/uploads/nutrition-facts.jpg',
        })
        .expect(200);
      expect(submitted.body.data).toMatchObject({
        foodId,
        status: 'pending',
        kind: 'barcode',
        barcode: '7622210449283',
        evidenceImageUrl: '/v1/uploads/nutrition-facts.jpg',
      });
      const candidateId = submitted.body.data.id as string;

      // 管理端审核队列：条码 + 佐证照片 + 营养值并排可见（「对答案」）
      const list = await request(server)
        .get('/v1/admin/food-candidates?status=pending')
        .set('x-admin-token', ADMIN)
        .expect(200);
      const row = (list.body.data.items as Array<Record<string, unknown>>).find(
        (c) => c.id === candidateId,
      );
      expect(row).toMatchObject({
        kind: 'barcode',
        barcode: '7622210449283',
        evidenceImageUrl: '/v1/uploads/nutrition-facts.jpg',
        per100g: { kcal: 100, proteinG: 10, carbG: 10, fatG: 5 },
      });

      await request(server)
        .post(`/v1/admin/food-candidates/${candidateId}/review`)
        .set('x-admin-token', ADMIN)
        .send({ action: 'approve' })
        .expect(200);

      // 共享 Food 带 barcode（后续扫码命中自有库）；任意用户 batch-get 可见
      const stranger = await login(nextPhone());
      const bg = await request(server)
        .post('/v1/foods/batch-get')
        .set(auth(stranger))
        .send({ ids: [foodId] })
        .expect(200);
      expect(bg.body.data.items[0]).toMatchObject({
        id: foodId,
        barcode: '7622210449283',
        source: 'community',
      });

      // 我的贡献列表带 kind/barcode
      const mine = await request(server)
        .get('/v1/foods/contributions')
        .set(auth(owner))
        .expect(200);
      const myRow = (mine.body.data.items as Array<Record<string, unknown>>).find(
        (c) => c.foodId === foodId,
      );
      expect(myRow).toMatchObject({
        kind: 'barcode',
        barcode: '7622210449283',
        status: 'approved',
      });
    });

    it('校验：条码无佐证照片 / 只传照片 / 条码格式非法 → 400', async () => {
      const owner = await login(nextPhone());
      const foodId = await createCustom(owner, '校验用条码糖');

      await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid(), barcode: '6901234567892' })
        .expect(400);
      await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid(), evidenceImageUrl: '/v1/uploads/x.jpg' })
        .expect(400);
      const bad = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({
          clientRequestId: nextUuid(),
          barcode: '123', // <8 位
          evidenceImageUrl: '/v1/uploads/x.jpg',
        })
        .expect(400);
      expect(bad.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('同条码查重：pending → 幂等返回已有候选；approved → 409 已上架', async () => {
      const ownerA = await login(nextPhone());
      const foodA = await createCustom(ownerA, '查重威化甲');
      const first = await request(server)
        .post(`/v1/foods/custom/${foodA}/contribute`)
        .set(auth(ownerA))
        .send({
          clientRequestId: nextUuid(),
          barcode: '6901234567892',
          evidenceImageUrl: '/v1/uploads/a.jpg',
        })
        .expect(200);
      const candidateId = first.body.data.id as string;

      // 另一用户同条码重复提交 → 幂等返回已有候选，不产生第二条
      const ownerB = await login(nextPhone());
      const foodB = await createCustom(ownerB, '查重威化乙');
      const dup = await request(server)
        .post(`/v1/foods/custom/${foodB}/contribute`)
        .set(auth(ownerB))
        .send({
          clientRequestId: nextUuid(),
          barcode: '6901234567892',
          evidenceImageUrl: '/v1/uploads/b.jpg',
        })
        .expect(200);
      expect(dup.body.data.id).toBe(candidateId);

      // 审核上架后，同条码再贡献 → 409 CONFLICT（已上架）
      await request(server)
        .post(`/v1/admin/food-candidates/${candidateId}/review`)
        .set('x-admin-token', ADMIN)
        .send({ action: 'approve' })
        .expect(200);
      const ownerC = await login(nextPhone());
      const foodC = await createCustom(ownerC, '查重威化丙');
      const conflict = await request(server)
        .post(`/v1/foods/custom/${foodC}/contribute`)
        .set(auth(ownerC))
        .send({
          clientRequestId: nextUuid(),
          barcode: '6901234567892',
          evidenceImageUrl: '/v1/uploads/c.jpg',
        })
        .expect(409);
      expect(conflict.body.error.code).toBe('CONFLICT');
    });

    it('自定义食物旧路径回归：不传 barcode → kind=custom，条码字段为 null', async () => {
      const owner = await login(nextPhone());
      const foodId = await createCustom(owner, '回归红烧肉');
      const res = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      expect(res.body.data).toMatchObject({
        status: 'pending',
        kind: 'custom',
        barcode: null,
        evidenceImageUrl: null,
      });
    });
  });

  describe('管理端 /v1/admin/food-candidates（x-admin-token）', () => {
    it('token 保护：缺 header / 错 token → 401', async () => {
      await request(server).get('/v1/admin/food-candidates').expect(401);
      await request(server)
        .get('/v1/admin/food-candidates')
        .set('x-admin-token', 'wrong')
        .expect(401);
      await request(server)
        .post('/v1/admin/food-candidates/fc_x/review')
        .set('x-admin-token', 'wrong')
        .send({ action: 'approve' })
        .expect(401);
    });

    it('队列查询：status 过滤 + 游标分页', async () => {
      const owner = await login(nextPhone());
      const id1 = await createCustom(owner, '队列食物一');
      const id2 = await createCustom(owner, '队列食物二');
      await request(server)
        .post(`/v1/foods/custom/${id1}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      await request(server)
        .post(`/v1/foods/custom/${id2}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);

      const page1 = await request(server)
        .get('/v1/admin/food-candidates?status=pending&limit=1')
        .set('x-admin-token', ADMIN)
        .expect(200);
      expect(page1.body.data.items).toHaveLength(1);
      expect(page1.body.data.pageInfo.hasMore).toBe(true);
      const page2 = await request(server)
        .get(
          `/v1/admin/food-candidates?status=pending&limit=1&cursor=${encodeURIComponent(
            page1.body.data.pageInfo.nextCursor as string,
          )}`,
        )
        .set('x-admin-token', ADMIN)
        .expect(200);
      expect(page2.body.data.items).toHaveLength(1);
      expect(page2.body.data.items[0].id).not.toBe(page1.body.data.items[0].id);

      // approved 过滤：只返回 approved（条码链路用例可能已产生 approved 候选）；非法 status → 400
      const approvedOnly = await request(server)
        .get('/v1/admin/food-candidates?status=approved')
        .set('x-admin-token', ADMIN)
        .expect(200);
      for (const c of approvedOnly.body.data.items as Array<{ status: string }>) {
        expect(c.status).toBe('approved');
      }
      await request(server)
        .get('/v1/admin/food-candidates?status=bogus')
        .set('x-admin-token', ADMIN)
        .expect(400);
    });

    it('approve → 晋升共享库（source=community 全用户可见，创建者溯源保留）；重复审核 → 409', async () => {
      const owner = await login(nextPhone());
      const stranger = await login(nextPhone());
      const foodId = await createCustom(owner, '晋升手抓饭');
      const contributed = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      const candidateId = contributed.body.data.id as string;

      const approved = await request(server)
        .post(`/v1/admin/food-candidates/${candidateId}/review`)
        .set('x-admin-token', ADMIN)
        .send({ action: 'approve' })
        .expect(200);
      expect(approved.body.data.status).toBe('approved');

      // 他人搜索可见：内置段命中，isCustom=false，source=community
      const theirs = await searchIds(stranger, '晋升手抓饭');
      const hit = theirs.find((i) => i.id === foodId);
      expect(hit).toBeDefined();
      expect(hit?.isCustom).toBe(false);
      expect(hit?.source).toBe('community');

      // 他人 batch-get 可见；创建者仍可见
      const bg = await request(server)
        .post('/v1/foods/batch-get')
        .set(auth(stranger))
        .send({ ids: [foodId] })
        .expect(200);
      expect(bg.body.data.items).toHaveLength(1);
      const mineBg = await request(server)
        .post('/v1/foods/batch-get')
        .set(auth(owner))
        .send({ ids: [foodId] })
        .expect(200);
      expect(mineBg.body.data.items).toHaveLength(1);

      // 已终审的候选重复审核 → 409
      await request(server)
        .post(`/v1/admin/food-candidates/${candidateId}/review`)
        .set('x-admin-token', ADMIN)
        .send({ action: 'reject' })
        .expect(409);
    });

    it('reject → 状态 rejected + reason；他人仍不可见，创建者仍按自定义可见', async () => {
      const owner = await login(nextPhone());
      const stranger = await login(nextPhone());
      const foodId = await createCustom(owner, '退回油泼面');
      const contributed = await request(server)
        .post(`/v1/foods/custom/${foodId}/contribute`)
        .set(auth(owner))
        .send({ clientRequestId: nextUuid() })
        .expect(200);
      const candidateId = contributed.body.data.id as string;

      const rejected = await request(server)
        .post(`/v1/admin/food-candidates/${candidateId}/review`)
        .set('x-admin-token', ADMIN)
        .send({ action: 'reject', reason: '营养数据存疑' })
        .expect(200);
      expect(rejected.body.data.status).toBe('rejected');
      expect(rejected.body.data.reason).toBe('营养数据存疑');

      // rejected：他人不可见，创建者仍可见（isCustom）
      const theirs = await searchIds(stranger, '退回油泼面');
      expect(theirs.find((i) => i.id === foodId)).toBeUndefined();
      const mine = await searchIds(owner, '退回油泼面');
      const hit = mine.find((i) => i.id === foodId);
      expect(hit).toBeDefined();
      expect(hit?.isCustom).toBe(true);

      // rejected 队列可按状态过滤到
      const list = await request(server)
        .get('/v1/admin/food-candidates?status=rejected')
        .set('x-admin-token', ADMIN)
        .expect(200);
      expect(
        (list.body.data.items as Array<{ id: string }>).find((c) => c.id === candidateId),
      ).toBeDefined();
    });

    it('审核不存在的候选 → 404', async () => {
      await request(server)
        .post('/v1/admin/food-candidates/fc_notexist/review')
        .set('x-admin-token', ADMIN)
        .send({ action: 'approve' })
        .expect(404);
    });
  });
});

/** 〔假设〕ADMIN_TOKEN 未配置时管理端点整体关闭（404，不暴露存在性） */
describe('Admin endpoints without ADMIN_TOKEN (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    delete process.env.ADMIN_TOKEN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
  });

  it('未配置 ADMIN_TOKEN → 管理端点 404', async () => {
    await request(server)
      .get('/v1/admin/food-candidates')
      .set('x-admin-token', 'whatever')
      .expect(404);
    await request(server)
      .post('/v1/admin/food-candidates/fc_x/review')
      .set('x-admin-token', 'whatever')
      .send({ action: 'approve' })
      .expect(404);
  });
});

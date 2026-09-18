import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

const ADMIN = 'test-admin-token';

/**
 * e2e：食物数据纠错（食物详情页「数据有误？」入口，kind=correction）。
 * 链路：共享食物（自定义贡献晋升）→ 另一用户提交纠错 → 管理端队列看到原值 vs 建议值 →
 * approve 应用建议值（全用户搜索可见新值）/ 校验与幂等口径。
 */
describe('Food correction (e2e)', () => {
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
    return `+8613933${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-correction', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  let uuidSeq = 0;
  function nextUuid(): string {
    uuidSeq += 1;
    return `c3d4e5f6-${String(uuidSeq).padStart(4, '0')}-4111-8111-111111111111`;
  }

  /** 造一个共享食物：自定义 → 贡献 → 管理端 approve 晋升，返回共享食物 id */
  async function createSharedFood(owner: string, nameZh: string): Promise<string> {
    const created = await request(server)
      .post('/v1/foods/custom')
      .set(auth(owner))
      .send({
        clientRequestId: nextUuid(),
        nameZh,
        per100g: { kcal: 100, proteinG: 10, carbG: 10, fatG: 5 },
        source: 'manual',
      })
      .expect(200);
    const foodId = created.body.data.id as string;
    await request(server)
      .post(`/v1/foods/custom/${foodId}/contribute`)
      .set(auth(owner))
      .send({ clientRequestId: nextUuid() })
      .expect(200);
    const queue = await request(server)
      .get('/v1/admin/food-candidates?status=pending&limit=50')
      .set('x-admin-token', ADMIN)
      .expect(200);
    const candidate = (queue.body.data.items as Array<{ id: string; foodId: string }>).find(
      (c) => c.foodId === foodId,
    );
    await request(server)
      .post(`/v1/admin/food-candidates/${candidate!.id}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(200);
    return foodId;
  }

  it('提交纠错 → 队列原值 vs 建议值 → approve 应用（搜索/详情取到新值）', async () => {
    const owner = await login(nextPhone());
    const reporter = await login(nextPhone());
    const foodId = await createSharedFood(owner, '纠错燕麦片');

    const res = await request(server)
      .post(`/v1/foods/${foodId}/correction`)
      .set(auth(reporter))
      .send({
        clientRequestId: nextUuid(),
        nameZh: '纠错燕麦片（即食）',
        per100g: { kcal: 350, proteinG: 12, carbG: 60, fatG: 7 },
      })
      .expect(200);
    expect(res.body.data.kind).toBe('correction');
    expect(res.body.data.status).toBe('pending');
    expect(res.body.data.suggestion).toMatchObject({
      nameZh: '纠错燕麦片（即食）',
      per100g: { kcal: 350, proteinG: 12, carbG: 60, fatG: 7 },
    });
    // 原值对照：per100g 为当前库值。
    expect(res.body.data.per100g).toMatchObject({ kcal: 100, proteinG: 10, carbG: 10, fatG: 5 });

    // 管理端队列：同一候选带 suggestion（审核台原值 vs 建议值）。
    const queue = await request(server)
      .get('/v1/admin/food-candidates?status=pending&limit=50')
      .set('x-admin-token', ADMIN)
      .expect(200);
    const candidate = (queue.body.data.items as Array<Record<string, any>>).find(
      (c) => c.id === res.body.data.id,
    );
    expect(candidate?.kind).toBe('correction');
    expect(candidate?.suggestion?.per100g?.kcal).toBe(350);

    await request(server)
      .post(`/v1/admin/food-candidates/${res.body.data.id}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(200);

    // 建议值已应用：任何用户搜索/详情取到新名称与新营养。
    const detail = await request(server)
      .post('/v1/foods/batch-get')
      .set(auth(reporter))
      .send({ ids: [foodId] })
      .expect(200);
    const item = (detail.body.data.items as Array<Record<string, any>>)[0];
    expect(item.nameZh).toBe('纠错燕麦片（即食）');
    expect(item.kcalPer100g).toBe(350);
    expect(item.proteinPer100g).toBe(12);
  });

  it('校验：未认证 401 / 目标不存在 404 / 营养越界 400 / 自定义食物 404', async () => {
    const owner = await login(nextPhone());
    const reporter = await login(nextPhone());
    const sharedId = await createSharedFood(owner, '纠错校验食品');
    const created = await request(server)
      .post('/v1/foods/custom')
      .set(auth(owner))
      .send({
        clientRequestId: nextUuid(),
        nameZh: '纠错私有食品',
        per100g: { kcal: 100, proteinG: 10, carbG: 10, fatG: 5 },
        source: 'manual',
      })
      .expect(200);
    const customId = created.body.data.id as string;

    await request(server)
      .post(`/v1/foods/${sharedId}/correction`)
      .send({ clientRequestId: nextUuid(), per100g: { kcal: 1, proteinG: 1, carbG: 1, fatG: 1 } })
      .expect(401);
    await request(server)
      .post('/v1/foods/f_missing/correction')
      .set(auth(reporter))
      .send({ clientRequestId: nextUuid(), per100g: { kcal: 1, proteinG: 1, carbG: 1, fatG: 1 } })
      .expect(404);
    // 自定义食物不在共享库：404（不泄露存在性）。
    await request(server)
      .post(`/v1/foods/${customId}/correction`)
      .set(auth(reporter))
      .send({ clientRequestId: nextUuid(), per100g: { kcal: 1, proteinG: 1, carbG: 1, fatG: 1 } })
      .expect(404);
    await request(server)
      .post(`/v1/foods/${sharedId}/correction`)
      .set(auth(reporter))
      .send({ clientRequestId: nextUuid(), per100g: { kcal: 901, proteinG: 1, carbG: 1, fatG: 1 } })
      .expect(400);
  });

  it('幂等与去重：同键重放返回首次；同人同食物 pending 重复提交返回原候选', async () => {
    const owner = await login(nextPhone());
    const reporter = await login(nextPhone());
    const foodId = await createSharedFood(owner, '纠错幂等食品');
    const reqId = nextUuid();
    const body = { clientRequestId: reqId, per100g: { kcal: 200, proteinG: 5, carbG: 5, fatG: 5 } };

    const first = await request(server)
      .post(`/v1/foods/${foodId}/correction`)
      .set(auth(reporter))
      .send(body)
      .expect(200);
    const replay = await request(server)
      .post(`/v1/foods/${foodId}/correction`)
      .set(auth(reporter))
      .send(body)
      .expect(200);
    expect(replay.body.data.id).toBe(first.body.data.id);

    // 新幂等键重复提交（不同建议值）：返回原候选，建议值不覆盖。
    const again = await request(server)
      .post(`/v1/foods/${foodId}/correction`)
      .set(auth(reporter))
      .send({ clientRequestId: nextUuid(), per100g: { kcal: 250, proteinG: 9, carbG: 9, fatG: 9 } })
      .expect(200);
    expect(again.body.data.id).toBe(first.body.data.id);
    expect(again.body.data.suggestion.per100g.kcal).toBe(200);

    // 我的贡献列表含该纠错条目。
    const mine = await request(server)
      .get('/v1/foods/contributions')
      .set(auth(reporter))
      .expect(200);
    const item = (mine.body.data.items as Array<Record<string, any>>).find(
      (c) => c.id === first.body.data.id,
    );
    expect(item?.kind).toBe('correction');
  });
});

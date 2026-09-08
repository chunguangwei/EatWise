import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

const ADMIN = 'test-admin-token';

/** e2e：我的贡献列表（众包状态批量查询 GET /v1/foods/contributions） */
describe('Food contributions list (e2e)', () => {
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
      .send({ phone, code: '123456', device: { deviceId: 'e2e-contrib', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  let uuidSeq = 0;
  function nextUuid(): string {
    uuidSeq += 1;
    return `c3d4e5f6-${String(uuidSeq).padStart(4, '0')}-4222-8222-222222222222`;
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

  async function contribute(token: string, foodId: string): Promise<string> {
    const res = await request(server)
      .post(`/v1/foods/custom/${foodId}/contribute`)
      .set(auth(token))
      .send({ clientRequestId: nextUuid() })
      .expect(200);
    return res.body.data.id as string;
  }

  async function review(
    candidateId: string,
    action: 'approve' | 'reject',
    reason?: string,
  ): Promise<void> {
    await request(server)
      .post(`/v1/admin/food-candidates/${candidateId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action, reason })
      .expect(200);
  }

  it('未认证 → 401', async () => {
    await request(server).get('/v1/foods/contributions').expect(401);
  });

  it('无贡献 → 空列表（items=[], total=0, 默认 page=1, pageSize=20）', async () => {
    const token = await login(nextPhone());
    const res = await request(server)
      .get('/v1/foods/contributions')
      .set(auth(token))
      .expect(200);
    expect(res.body.data.items).toEqual([]);
    expect(res.body.data.total).toBe(0);
    expect(res.body.data.page).toBe(1);
    expect(res.body.data.pageSize).toBe(20);
  });

  it('只返回本人的候选，缺省全部状态，createdAt 倒序', async () => {
    const me = await login(nextPhone());
    const other = await login(nextPhone());

    const foodA = await createCustom(me, '贡献列表甲');
    const candidateA = await contribute(me, foodA);
    const otherFood = await createCustom(other, '他人贡献物');
    const otherCandidate = await contribute(other, otherFood);
    const foodB = await createCustom(me, '贡献列表乙');
    const candidateB = await contribute(me, foodB);

    const res = await request(server)
      .get('/v1/foods/contributions')
      .set(auth(me))
      .expect(200);
    const ids = res.body.data.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(candidateA);
    expect(ids).toContain(candidateB);
    expect(ids).not.toContain(otherCandidate);
    expect(res.body.data.total).toBe(2);

    // createdAt 倒序：后提交的 candidateB 在前
    expect(ids[0]).toBe(candidateB);
    expect(ids[1]).toBe(candidateA);

    const item = res.body.data.items[0];
    expect(item).toMatchObject({
      id: candidateB,
      foodId: foodB,
      status: 'pending',
      reason: null,
    });
    expect(typeof item.createdAt).toBe('string');
    expect(typeof item.updatedAt).toBe('string');
  });

  it('status 过滤：pending / approved / rejected', async () => {
    const me = await login(nextPhone());
    const pendingFood = await createCustom(me, '过滤待审');
    const pendingCandidate = await contribute(me, pendingFood);
    const approvedFood = await createCustom(me, '过滤通过');
    const approvedCandidate = await contribute(me, approvedFood);
    await review(approvedCandidate, 'approve');
    const rejectedFood = await createCustom(me, '过滤退回');
    const rejectedCandidate = await contribute(me, rejectedFood);
    await review(rejectedCandidate, 'reject', '营养数据存疑');

    const pending = await request(server)
      .get('/v1/foods/contributions?status=pending')
      .set(auth(me))
      .expect(200);
    const pendingIds = pending.body.data.items.map((i: { id: string }) => i.id);
    expect(pendingIds).toContain(pendingCandidate);
    expect(pendingIds).not.toContain(approvedCandidate);
    expect(pendingIds).not.toContain(rejectedCandidate);

    const approved = await request(server)
      .get('/v1/foods/contributions?status=approved')
      .set(auth(me))
      .expect(200);
    expect(approved.body.data.items.map((i: { id: string }) => i.id)).toEqual([approvedCandidate]);

    const rejected = await request(server)
      .get('/v1/foods/contributions?status=rejected')
      .set(auth(me))
      .expect(200);
    expect(rejected.body.data.items.map((i: { id: string }) => i.id)).toEqual([rejectedCandidate]);
    expect(rejected.body.data.items[0].reason).toBe('营养数据存疑');
  });

  it('分页：page/pageSize 生效，pageSize 封顶 50，越界页空 items', async () => {
    const me = await login(nextPhone());
    for (let i = 0; i < 3; i += 1) {
      await contribute(me, await createCustom(me, `分页食物${i}`));
    }

    const page1 = await request(server)
      .get('/v1/foods/contributions?page=1&pageSize=2')
      .set(auth(me))
      .expect(200);
    expect(page1.body.data.items).toHaveLength(2);
    expect(page1.body.data.total).toBe(3);
    expect(page1.body.data.page).toBe(1);
    expect(page1.body.data.pageSize).toBe(2);

    const page2 = await request(server)
      .get('/v1/foods/contributions?page=2&pageSize=2')
      .set(auth(me))
      .expect(200);
    expect(page2.body.data.items).toHaveLength(1);

    const page3 = await request(server)
      .get('/v1/foods/contributions?page=3&pageSize=2')
      .set(auth(me))
      .expect(200);
    expect(page3.body.data.items).toEqual([]);

    // pageSize 封顶 50，total 仍为真实总数
    const capped = await request(server)
      .get('/v1/foods/contributions?pageSize=999')
      .set(auth(me))
      .expect(200);
    expect(capped.body.data.pageSize).toBe(50);
    expect(capped.body.data.total).toBe(3);

    // page=0 / 非数字 → 回退到 1
    const badPage = await request(server)
      .get('/v1/foods/contributions?page=0')
      .set(auth(me))
      .expect(200);
    expect(badPage.body.data.page).toBe(1);
  });

  it('非法 status → 400 校验错误', async () => {
    const me = await login(nextPhone());
    const res = await request(server)
      .get('/v1/foods/contributions?status=bogus')
      .set(auth(me))
      .expect(400);
    expect(res.body.error.code).toBeDefined();
  });
});

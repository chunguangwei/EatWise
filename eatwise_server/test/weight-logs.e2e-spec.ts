import { randomUUID } from 'crypto';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：阶段 C 体重记录端点（POST/GET/DELETE /v1/weight-logs，鉴权 + 幂等 + 校验） */
describe('Weight logs API (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;
  let otherToken: string;

  const login = async (phone: string, deviceId: string): Promise<string> => {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId, platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
    token = await login('+8613923000001', 'e2e-weight-a');
    otherToken = await login('+8613923000002', 'e2e-weight-b');
  });

  afterAll(async () => {
    await app.close();
  });

  const post = (body: Record<string, unknown>, auth = token) =>
    request(server).post('/v1/weight-logs').set('Authorization', `Bearer ${auth}`).send(body);

  const validBody = (over: Record<string, unknown> = {}) => ({
    clientRequestId: randomUUID(),
    date: '2026-09-17',
    weightKg: 65.5,
    ...over,
  });

  it('未鉴权 → 401', async () => {
    await request(server).post('/v1/weight-logs').send(validBody()).expect(401);
    await request(server).get('/v1/weight-logs').expect(401);
    await request(server).delete('/v1/weight-logs/some-id').expect(401);
  });

  it('POST 创建（含体脂率）→ 200；幂等重放同结果', async () => {
    const body = validBody({ bodyFatPct: 18.2 });
    const res = await post(body).expect(200);
    const view = res.body.data;
    expect(view.id).toBeTruthy();
    expect(view.weightKg).toBe(65.5);
    expect(view.bodyFatPct).toBe(18.2);
    expect(view.version).toBe(1);

    const replay = await post(body).expect(200);
    expect(replay.body.data.id).toBe(view.id);
  });

  it('POST 同日覆写：同 date 新幂等键 → 同一行 version+1', async () => {
    const first = await post(validBody({ date: '2026-09-10', weightKg: 70 })).expect(200);
    const second = await post(validBody({ date: '2026-09-10', weightKg: 69.2 })).expect(200);
    expect(second.body.data.id).toBe(first.body.data.id);
    expect(second.body.data.weightKg).toBe(69.2);
    expect(second.body.data.version).toBe(2);
  });

  it('POST 同键不同体 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const body = validBody({ date: '2026-09-11' });
    await post(body).expect(200);
    const res = await post({ ...body, weightKg: 99 }).expect(409);
    expect(res.body.error.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
  });

  it('POST 参数校验：缺 clientRequestId / 体重超范围 / 日期格式错 → 400', async () => {
    expect((await post({ date: '2026-09-12', weightKg: 60 })).status).toBe(400);
    expect((await post(validBody({ date: '2026-09-12', weightKg: 500 }))).status).toBe(400);
    expect((await post(validBody({ date: '2026-09-12', weightKg: 5 }))).status).toBe(400);
    expect((await post(validBody({ date: '2026/09/12' }))).status).toBe(400);
    expect((await post(validBody({ date: '2026-09-12', bodyFatPct: 120 }))).status).toBe(400);
  });

  it('GET 区间查询：含端点、date 升序、排除他用户', async () => {
    await post(validBody({ date: '2026-09-01', weightKg: 67 })).expect(200);
    await post(validBody({ date: '2026-09-03', weightKg: 66.4 })).expect(200);
    await post(validBody({ date: '2026-09-02', weightKg: 66.7 })).expect(200);
    await post(validBody({ date: '2026-09-02', weightKg: 80 }), otherToken).expect(200);

    const res = await request(server)
      .get('/v1/weight-logs?from=2026-09-01&to=2026-09-02')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(res.body.data.logs.map((l: { date: string }) => l.date)).toEqual([
      '2026-09-01',
      '2026-09-02',
    ]);

    // 非法区间 → 400
    await request(server)
      .get('/v1/weight-logs?from=2026-09-05&to=2026-09-01')
      .set('Authorization', `Bearer ${token}`)
      .expect(400);
  });

  it('DELETE 软删：区间查询排除；重复删除幂等；他人记录 404', async () => {
    const created = await post(validBody({ date: '2026-09-05', weightKg: 65 })).expect(200);
    const id = created.body.data.id as string;

    await request(server)
      .delete(`/v1/weight-logs/${id}`)
      .set('Authorization', `Bearer ${otherToken}`)
      .expect(404);

    const del = await request(server)
      .delete(`/v1/weight-logs/${id}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(del.body.data.deletedAt).toBeTruthy();

    const list = await request(server)
      .get('/v1/weight-logs?from=2026-09-05&to=2026-09-05')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(list.body.data.logs).toHaveLength(0);

    // 重复删除幂等 200
    await request(server)
      .delete(`/v1/weight-logs/${id}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  });
});

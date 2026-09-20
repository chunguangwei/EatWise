import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：P4 自选进食窗口上行 → P3 回显；跨午夜窗口合法；窗口时长与 planType 不一致 400 */
describe('Fasting plan custom window (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
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

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-plan', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const put = (token: string, body: Record<string, unknown>) =>
    request(server)
      .put('/v1/fasting-plans/current')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .send(body);

  const get = (token: string) =>
    request(server)
      .get('/v1/fasting-plans/current')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai');

  it('首个方案 PUT 立即生效 → GET 回显自选窗口；改动仍 pending 次日', async () => {
    const token = await login('+8613911000101');
    const res = await put(token, {
      clientRequestId: randomUUID(),
      planType: '16:8',
      eatingWindow: { start: '09:00', end: '17:00' },
    }).expect(200);
    expect(res.body.data.current.status).toBe('current');
    expect(res.body.data.current.eatingWindow).toEqual({ start: '09:00', end: '17:00' });

    const got = await get(token).expect(200);
    expect(got.body.data.current.planType).toBe('16:8');
    expect(got.body.data.current.eatingWindow).toEqual({ start: '09:00', end: '17:00' });
    expect(got.body.data.pending).toBeNull();

    // 已有方案 → 改动 pending 次日生效，current 不变（D-06）
    const res2 = await put(token, {
      clientRequestId: randomUUID(),
      planType: '14:10',
      eatingWindow: { start: '08:00', end: '18:00' },
    }).expect(200);
    expect(res2.body.data.pending.status).toBe('pending');
    expect(res2.body.data.pending.planType).toBe('14:10');
    expect(res2.body.data.current.planType).toBe('16:8');

    const got2 = await get(token).expect(200);
    // pending 为原始实体形状（契约不变形）：eatingWindowStart/End 平铺字段
    expect(got2.body.data.pending.planType).toBe('14:10');
    expect(got2.body.data.pending.eatingWindowStart).toBe('08:00');
    expect(got2.body.data.pending.eatingWindowEnd).toBe('18:00');
  });

  it('跨午夜窗口合法（18:6 配 21:00–03:00）：PUT 成功且 GET 回显', async () => {
    const token = await login('+8613911000102');
    await put(token, {
      clientRequestId: randomUUID(),
      planType: '18:6',
      eatingWindow: { start: '21:00', end: '03:00' },
    }).expect(200);
    const got = await get(token).expect(200);
    expect(got.body.data.current.eatingWindow).toEqual({ start: '21:00', end: '03:00' });
    // 计时环口径同步：status 回显同一窗口
    const status = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    expect(status.body.data.plan.eatingWindow).toEqual({ start: '21:00', end: '03:00' });
  });

  it('窗口时长与 planType 不一致 → 400 VALIDATION_ERROR；planType 非法 → 400', async () => {
    const token = await login('+8613911000103');
    const bad = await put(token, {
      clientRequestId: randomUUID(),
      planType: '16:8',
      eatingWindow: { start: '09:00', end: '19:00' }, // 10h ≠ 8h
    }).expect(400);
    expect(bad.body.error.code).toBe('VALIDATION_ERROR');
    // 拒绝后不落库：GET 仍是 16:8 12:00–20:00 兜底（D-03）
    const got = await get(token).expect(200);
    expect(got.body.data.current.planType).toBe('16:8');
    expect(got.body.data.current.eatingWindow).toEqual({ start: '12:00', end: '20:00' });

    const badType = await put(token, {
      clientRequestId: randomUUID(),
      planType: '20:4',
      eatingWindow: { start: '10:00', end: '14:00' },
    }).expect(400);
    expect(badType.body.error.code).toBe('VALIDATION_ERROR');
  });
});

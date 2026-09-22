import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：U2 PATCH /users/me DTO 校验（timezone IANA 合法性 / 数值范围） */
describe('User profile patch validation (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    await request(server)
      .post('/v1/auth/sms/send')
      .send({ phone: '+8613922000001', scene: 'login' })
      .expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({
        phone: '+8613922000001',
        code: '123456',
        device: { deviceId: 'e2e-profile', platform: 'ios' },
      })
      .expect(200);
    token = res.body.data.accessToken as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const patch = (body: Record<string, unknown>) =>
    request(server).patch('/v1/users/me').set('Authorization', `Bearer ${token}`).send(body);

  it('合法资料 → 200 落库（timezone/birthYear/heightCm/weightKg）', async () => {
    const res = await patch({
      nickname: '小林',
      timezone: 'Asia/Shanghai',
      birthYear: 1998,
      heightCm: 168,
      weightKg: 60.5,
    }).expect(200);
    expect(res.body.data.user.timezone).toBe('Asia/Shanghai');
    expect(res.body.data.user.birthYear).toBe(1998);
    expect(res.body.data.user.heightCm).toBe(168);
  });

  it('非法 timezone → 400 VALIDATION_ERROR（不落库）', async () => {
    const res = await patch({ timezone: 'Not/AZone' }).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.data.user.timezone).toBe('Asia/Shanghai'); // 上一个合法值未被覆盖
  });

  it('birthYear 超范围 / 非整数 → 400', async () => {
    expect((await patch({ birthYear: 1800 })).status).toBe(400);
    expect((await patch({ birthYear: new Date().getUTCFullYear() + 1 })).status).toBe(400);
    expect((await patch({ birthYear: 1998.5 })).status).toBe(400);
    expect((await patch({ birthYear: '1998' })).status).toBe(400);
  });

  it('heightCm / weightKg 超范围 → 400', async () => {
    expect((await patch({ heightCm: 400 })).status).toBe(400);
    expect((await patch({ heightCm: 10 })).status).toBe(400);
    expect((await patch({ weightKg: 1000 })).status).toBe(400);
    expect((await patch({ weightKg: -5 })).status).toBe(400);
  });

  it('onboardingStatus 可 PATCH（none/completed/skipped），非法值 → 400', async () => {
    const res = await patch({ onboardingStatus: 'completed' }).expect(200);
    expect(res.body.data.user.onboardingStatus).toBe('completed');

    const skipped = await patch({ onboardingStatus: 'skipped' }).expect(200);
    expect(skipped.body.data.user.onboardingStatus).toBe('skipped');

    // 非法枚举 → 400 且不落库
    expect((await patch({ onboardingStatus: 'done' })).status).toBe(400);
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.data.user.onboardingStatus).toBe('skipped');
  });

  it('D-21 settingsPrefs 偏好同步包：PATCH 落库 + getMe 回显，syncedAt 服务端打戳，对象外类型 → 400', async () => {
    const prefs = {
      locale: 'zh-CN',
      theme: 'system',
      weightUnit: 'jin',
      burnGoalKcal: 500,
      stepsGoal: 8000,
      syncedAt: '2026-09-18T08:00:00.000Z',
    };
    const res = await patch({ settingsPrefs: prefs }).expect(200);
    // LWW 时间戳由服务端时钟统一打（走查 L6）：客户端自报值被忽略。
    const stamped = res.body.data.user.settingsPrefs;
    expect(stamped).toEqual({ ...prefs, syncedAt: expect.any(String) });
    expect(stamped.syncedAt).not.toBe(prefs.syncedAt);
    expect(Math.abs(Date.parse(stamped.syncedAt) - Date.now())).toBeLessThan(60_000);

    // 字段级 LWW：只改部分键时整个 JSON 包整体替换（客户端约定整包推送）
    const next = { ...prefs, theme: 'dark', syncedAt: '2026-09-18T09:00:00.000Z' };
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.data.user.settingsPrefs).toEqual(stamped);

    const res2 = await patch({ settingsPrefs: next }).expect(200);
    const stamped2 = res2.body.data.user.settingsPrefs;
    expect(stamped2).toEqual({ ...next, syncedAt: expect.any(String) });
    expect(Date.parse(stamped2.syncedAt)).toBeGreaterThanOrEqual(Date.parse(stamped.syncedAt));

    // 非对象类型 → DTO 校验拒绝
    expect((await patch({ settingsPrefs: 'dark' })).status).toBe(400);
    expect((await patch({ settingsPrefs: 42 })).status).toBe(400);
  });

  it('阶段 B 减重目标：targetWeightKg/targetDate 合法 → 200 落库并以日期口径回显', async () => {
    const future = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
    const res = await patch({ targetWeightKg: 62.5, targetDate: future }).expect(200);
    expect(res.body.data.user.targetWeightKg).toBe(62.5);
    expect(res.body.data.user.targetDate).toBe(future);

    // 可清空（null 透传）
    const cleared = await patch({ targetWeightKg: null, targetDate: null }).expect(200);
    expect(cleared.body.data.user.targetWeightKg).toBeNull();
    expect(cleared.body.data.user.targetDate).toBeNull();
  });

  it('阶段 B 减重目标校验：targetWeightKg 超范围 / targetDate 非未来或超 2 年 → 400', async () => {
    expect((await patch({ targetWeightKg: 10 })).status).toBe(400);
    expect((await patch({ targetWeightKg: 400 })).status).toBe(400);
    expect((await patch({ targetDate: '2020-01-01' })).status).toBe(400); // 过去
    expect((await patch({ targetDate: new Date().toISOString().slice(0, 10) })).status).toBe(400); // 今天不算未来
    const over2y = new Date(
      Date.UTC(
        new Date().getUTCFullYear() + 2,
        new Date().getUTCMonth(),
        new Date().getUTCDate() + 1,
      ),
    )
      .toISOString()
      .slice(0, 10);
    expect((await patch({ targetDate: over2y })).status).toBe(400);
    expect((await patch({ targetDate: '2026-02-30' })).status).toBe(400); // 伪日期
    expect((await patch({ targetDate: 'next month' })).status).toBe(400);
  });
});

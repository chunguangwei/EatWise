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
});

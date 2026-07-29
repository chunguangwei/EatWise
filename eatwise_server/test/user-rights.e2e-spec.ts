import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** U3 导出 / U5 删除冷静期 / U6 撤销 / 登录即撤销 / U1 手机号脱敏（e2e，memory 驱动） */
describe('用户权利 (e2e)', () => {
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

  let seq = 100;
  function nextPhone(): string {
    seq += 1;
    return `+8613800${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string) {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-rights', platform: 'ios' } })
      .expect(200);
    return res.body.data as {
      accessToken: string;
      refreshToken: string;
      deletionCancelled: boolean;
    };
  }

  async function firstFoodId(token: string): Promise<string> {
    const res = await request(server)
      .get('/v1/foods/search?q=%E9%B8%A1%E8%9B%8B')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    return res.body.data.items[0].id as string;
  }

  it('U1：users/me 返回脱敏手机号（138****8000 格式）', async () => {
    const phone = nextPhone();
    const { accessToken } = await login(phone);
    const res = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(res.body.data.user.phone).toMatch(/^\d{3}\*{4}\d{4}$/);
    expect(JSON.stringify(res.body.data.user)).not.toContain(phone.slice(3)); // 不含明文
  });

  it('U3：导出聚合该用户全量数据（profile/foodEntries/…）', async () => {
    const { accessToken } = await login(nextPhone());
    const foodId = await firstFoodId(accessToken);
    await request(server)
      .post('/v1/food-entries')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        clientRequestId: '9b7b06d2-6f6f-4f2a-9d3a-7f0f2a1b0001',
        eatenAt: new Date().toISOString(),
        foodId,
        grams: 100,
        inputMethod: 'manual',
      })
      .expect(200);

    const res = await request(server)
      .post('/v1/users/me/export')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);
    const bundle = res.body.data;
    expect(bundle.generatedAt).toMatch(/Z$/);
    expect(bundle.profile.id).toBeTruthy();
    expect(bundle.profile.phone).toMatch(/^\+86/); // 本人导出含明文手机号
    expect(bundle.foodEntries).toHaveLength(1);
    expect(bundle.foodEntries[0].foodId).toBe(foodId);
    expect(bundle.fastingRecords).toEqual([]);
    expect(bundle.posts).toEqual([]);
    expect(bundle).toHaveProperty('streak');
    expect(bundle).toHaveProperty('fastingPlans');
  });

  it('U5/U6：申请删除 → 冷静期标记 + 会话吊销 → 撤销', async () => {
    const { accessToken, refreshToken } = await login(nextPhone());

    const del = await request(server)
      .post('/v1/users/me/deletion')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);
    expect(del.body.data.deletionStatus).toBe('pending');
    expect(del.body.data.coolingOffDays).toBe(7);
    const scheduled = new Date(del.body.data.scheduledDeletionAt).getTime();
    expect(scheduled).toBeGreaterThan(Date.now() + 6 * 24 * 3600 * 1000);

    // 幂等：重复申请返回在途任务，时间不后移
    const again = await request(server)
      .post('/v1/users/me/deletion')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);
    expect(again.body.data.scheduledDeletionAt).toBe(del.body.data.scheduledDeletionAt);

    // 立即登出所有会话：refresh token 已吊销
    await request(server).post('/v1/auth/refresh').send({ refreshToken }).expect(401);

    // U6 撤销（access token 仍有效）
    const cancel = await request(server)
      .delete('/v1/users/me/deletion')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(cancel.body.data.deletionStatus).toBeNull();

    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(me.body.data.user.deletionStatus).toBeNull();
    expect(me.body.data.user.scheduledDeletionAt).toBeNull();
  });

  it('冷静期内重新登录即视为撤销（合规 §4.3），响应明示 deletionCancelled', async () => {
    const phone = nextPhone();
    const { accessToken } = await login(phone);
    await request(server)
      .post('/v1/users/me/deletion')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    const relogin = await login(phone);
    expect(relogin.deletionCancelled).toBe(true);

    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${relogin.accessToken}`)
      .expect(200);
    expect(me.body.data.user.deletionStatus).toBeNull();
  });
});

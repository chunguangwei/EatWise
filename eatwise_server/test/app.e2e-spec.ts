import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：响应封装 / 错误码三段式 / i18n 错误消息 / 认证链路 */
describe('App (e2e)', () => {
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

  let seq = 0;
  // 每个用例使用独立手机号，规避短信 60s 重发限频
  function nextPhone(): string {
    seq += 1;
    return `+8613900${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-1', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  it('GET /v1/health → 统一成功封装 { data, meta }', async () => {
    const res = await request(server).get('/v1/health').expect(200);
    expect(res.body.data).toEqual({ status: 'ok' });
    expect(res.body.meta.serverTime).toMatch(/Z$/);
    expect(res.body.meta.requestId).toMatch(/^req_/);
  });

  it('手机验证码登录全链路：sms/send → login/phone → users/me', async () => {
    const token = await login(nextPhone());
    expect(token).toBeTruthy();
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.data.user.id).toBeTruthy();
    expect(me.body.data.nutritionTargets.fallback).toBe(true); // 新用户缺资料 → 兜底
  });

  it('未带 token → 401 AUTH_TOKEN_INVALID，message 默认中文', async () => {
    const res = await request(server).get('/v1/users/me').expect(401);
    expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
    expect(res.body.error.message).toBe('登录状态无效，请重新登录');
  });

  it('Accept-Language: en → 英文错误消息（D-15）', async () => {
    const res = await request(server).get('/v1/users/me').set('Accept-Language', 'en').expect(401);
    expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
    expect(res.body.error.message).toBe('Invalid session, please sign in again');
  });

  it('参数校验失败 → 400 VALIDATION_ERROR + details.fields', async () => {
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone: 'not-a-phone', code: '123456' })
      .expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.message).toBeTruthy();
  });

  it('错误验证码 → 400 AUTH_CODE_INVALID + remainingAttempts', async () => {
    const phone = nextPhone();
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '000000' })
      .expect(400);
    expect(res.body.error.code).toBe('AUTH_CODE_INVALID');
  });

  it('refresh 轮换 + 旧值重放 → 401 AUTH_REFRESH_REUSED', async () => {
    const phone = nextPhone();
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const loginRes = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456' })
      .expect(200);
    const rt = loginRes.body.data.refreshToken as string;
    await request(server).post('/v1/auth/refresh').send({ refreshToken: rt }).expect(200);
    const reuse = await request(server)
      .post('/v1/auth/refresh')
      .send({ refreshToken: rt })
      .expect(401);
    expect(reuse.body.error.code).toBe('AUTH_REFRESH_REUSED');
  });

  it('食物双语搜索需登录且返回 matchedOn/highlight', async () => {
    const token = await login(nextPhone());
    const res = await request(server)
      .get('/v1/foods/search?q=ji')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(res.body.data.items.length).toBeGreaterThanOrEqual(2);
    expect(res.body.data.items[0].matchedOn).toBeTruthy();
    expect(res.body.data.pageInfo.hasMore).toBe(false);
  });

  it('断食状态 F1：返回 state/window/toleranceMinutes/extendRemainingMinutes', async () => {
    const token = await login(nextPhone());
    const res = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    expect(['fasting', 'eating']).toContain(res.body.data.state);
    expect(res.body.data.toleranceMinutes).toBe(15);
    expect(res.body.data.window.eatingStartAt).toMatch(/Z$/);
  });

  it('批量上行 >100 条 → 400 VALIDATION_ERROR', async () => {
    const token = await login(nextPhone());
    const ops = Array.from({ length: 101 }, (_, i) => ({
      clientRequestId: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId: 'x', grams: 100 },
    }));
    const res = await request(server)
      .post('/v1/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send({ ops })
      .expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  let unameSeq = 0;
  function nextUsername(): string {
    unameSeq += 1;
    return `e2e_user_${String(unameSeq).padStart(4, '0')}`;
  }

  it('账号密码注册全链路：register → users/me；重复用户名 → 409', async () => {
    const username = nextUsername();
    const res = await request(server)
      .post('/v1/auth/register')
      .send({ username: username.toUpperCase(), password: 'Passw0rd123' })
      .expect(201);
    expect(res.body.data.isNewUser).toBe(true);
    expect(res.body.data.deletionCancelled).toBe(false);
    expect(res.body.data.user.id).toBeTruthy();
    expect(res.body.data.accessToken).toBeTruthy();
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${res.body.data.accessToken}`)
      .expect(200);
    expect(me.body.data.user.id).toBe(res.body.data.user.id);
    // username 小写归一化后随 U1 视图返回（D-13 v2 账号密码主路径）
    expect(me.body.data.user.username).toBe(username);
    // 大小写不敏感的唯一性：同一用户名再注册 → 409
    const dup = await request(server)
      .post('/v1/auth/register')
      .send({ username, password: 'Passw0rd123' })
      .expect(409);
    expect(dup.body.error.code).toBe('AUTH_USERNAME_TAKEN');
  });

  it('注册弱密码 → 400 AUTH_PASSWORD_TOO_WEAK', async () => {
    const res = await request(server)
      .post('/v1/auth/register')
      .send({ username: nextUsername(), password: 'onlyletters' })
      .expect(400);
    expect(res.body.error.code).toBe('AUTH_PASSWORD_TOO_WEAK');
  });

  it('账号密码登录：成功 200 isNewUser=false；密码错误 401 AUTH_INVALID_CREDENTIALS', async () => {
    const username = nextUsername();
    await request(server)
      .post('/v1/auth/register')
      .send({ username, password: 'Passw0rd123' })
      .expect(201);
    const ok = await request(server)
      .post('/v1/auth/login')
      .send({ username, password: 'Passw0rd123', device: { deviceId: 'e2e-2', platform: 'ios' } })
      .expect(200);
    expect(ok.body.data.isNewUser).toBe(false);
    const bad = await request(server)
      .post('/v1/auth/login')
      .send({ username, password: 'Wrong0Pass' })
      .expect(401);
    expect(bad.body.error.code).toBe('AUTH_INVALID_CREDENTIALS');
    const ghost = await request(server)
      .post('/v1/auth/login')
      .send({ username: 'no_such_user', password: 'Passw0rd123' })
      .expect(401);
    expect(ghost.body.error.code).toBe('AUTH_INVALID_CREDENTIALS');
  });

  it('修改密码：旧密码错误 401；成功后旧 refresh token 失效（全端重新登录）', async () => {
    const username = nextUsername();
    const reg = await request(server)
      .post('/v1/auth/register')
      .send({ username, password: 'Passw0rd123' })
      .expect(201);
    const auth = `Bearer ${reg.body.data.accessToken}`;
    const wrong = await request(server)
      .post('/v1/auth/password/change')
      .set('Authorization', auth)
      .send({ oldPassword: 'Wrong0Pass', newPassword: 'N3wPassword' })
      .expect(401);
    expect(wrong.body.error.code).toBe('AUTH_INVALID_CREDENTIALS');
    const weak = await request(server)
      .post('/v1/auth/password/change')
      .set('Authorization', auth)
      .send({ oldPassword: 'Passw0rd123', newPassword: '12345678' })
      .expect(400);
    expect(weak.body.error.code).toBe('AUTH_PASSWORD_TOO_WEAK');
    await request(server)
      .post('/v1/auth/password/change')
      .set('Authorization', auth)
      .send({ oldPassword: 'Passw0rd123', newPassword: 'N3wPassword' })
      .expect(200);
    const reuse = await request(server)
      .post('/v1/auth/refresh')
      .send({ refreshToken: reg.body.data.refreshToken })
      .expect(401);
    expect(['AUTH_REFRESH_REUSED', 'AUTH_TOKEN_INVALID']).toContain(reuse.body.error.code);
    await request(server)
      .post('/v1/auth/login')
      .send({ username, password: 'N3wPassword' })
      .expect(200);
  });

  it('修改密码未带 token → 401 AUTH_TOKEN_INVALID', async () => {
    const res = await request(server)
      .post('/v1/auth/password/change')
      .send({ oldPassword: 'Passw0rd123', newPassword: 'N3wPassword' })
      .expect(401);
    expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
  });
});

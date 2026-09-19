import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';

const ADMIN_TOKEN = 'test-admin-token';
const ROOT = { username: 'root', password: 'root-pass-123' };
const REVIEWER = { username: 'reviewer1', password: 'rev-pass-123' };
const PWADMIN = { username: 'pwadmin', password: 'old-pass-1234' };
const PWADMIN2 = { username: 'pwadmin2', password: 'old-pass-1234' };
const PWADMIN3 = { username: 'pwadmin3', password: 'old-pass-1234' };

/**
 * e2e：管理员账号体系（/v1/admin/auth/* + AdminAuthGuard + @AdminRole 角色门）。
 * 覆盖：种子账号创建、登录成功/错误密码/disabled 拒登/限流 5 次每分钟、
 * JWT 鉴权与禁用即刻失效、角色门（reviewer 可调审核端点）、
 * x-admin-token 兜底兼容（视为 admin）。
 * 注意：登录限流按用户名计数（5 次/分钟），各用例使用不同用户名避免相互干扰。
 */
describe('Admin auth & roles (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let store: DataStore;
  let rootJwt: string;
  let reviewerJwt: string;

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN_TOKEN;
    process.env.ADMIN_USERNAME = ROOT.username;
    process.env.ADMIN_PASSWORD = ROOT.password;

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
    store = app.get(DataStore);

    // 直接落库：reviewer 角色账号 + 禁用账号（管理端暂无账号管理接口〔假设〕）
    store.createAdminUser({
      username: REVIEWER.username,
      passwordHash: bcrypt.hashSync(REVIEWER.password, 10),
      role: 'reviewer',
      disabled: false,
    });
    store.createAdminUser({
      username: 'disabled1',
      passwordHash: bcrypt.hashSync('disabled-pass-123', 10),
      role: 'admin',
      disabled: true,
    });
    // 改密用例专用账号（独立用户名，避免与登录限流按用户名计数相互干扰）
    for (const acc of [PWADMIN, PWADMIN2, PWADMIN3]) {
      store.createAdminUser({
        username: acc.username,
        passwordHash: bcrypt.hashSync(acc.password, 10),
        role: 'admin',
        disabled: false,
      });
    }
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
    delete process.env.ADMIN_USERNAME;
    delete process.env.ADMIN_PASSWORD;
  });

  describe('种子账号', () => {
    it('启动时按 ADMIN_USERNAME/ADMIN_PASSWORD 创建 admin 角色账号（bcrypt 存储）', () => {
      const seed = store.findAdminByUsername(ROOT.username);
      expect(seed).toBeDefined();
      expect(seed!.role).toBe('admin');
      expect(seed!.disabled).toBe(false);
      expect(seed!.passwordHash).not.toContain(ROOT.password);
      expect(bcrypt.compareSync(ROOT.password, seed!.passwordHash)).toBe(true);
    });
  });

  describe('POST /v1/admin/auth/login', () => {
    it('登录成功 → 管理员 JWT + admin 信息（role=admin）', async () => {
      const res = await request(server).post('/v1/admin/auth/login').send(ROOT).expect(200);
      expect(res.body.data.accessToken).toBeTruthy();
      expect(res.body.data.expiresIn).toBe(43200);
      expect(res.body.data.admin).toMatchObject({ username: ROOT.username, role: 'admin' });
      rootJwt = res.body.data.accessToken;
    });

    it('错误密码 → 401（不泄露账号是否存在）', async () => {
      const res = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: ROOT.username, password: 'wrong-pass' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
      const res2 = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: 'no-such-user', password: 'whatever' })
        .expect(401);
      expect(res2.body.error.code).toBe('AUTH_TOKEN_INVALID');
    });

    it('disabled 账号拒登 → 401', async () => {
      await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: 'disabled1', password: 'disabled-pass-123' })
        .expect(401);
    });

    it('限流：同一用户名 5 次/分钟，第 6 次 → 429 RATE_LIMITED', async () => {
      for (let i = 0; i < 5; i++) {
        await request(server)
          .post('/v1/admin/auth/login')
          .send({ username: 'rl-user', password: 'x' })
          .expect(401);
      }
      const res = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: 'rl-user', password: 'x' })
        .expect(429);
      expect(res.body.error.code).toBe('RATE_LIMITED');
    });
  });

  describe('JWT 鉴权与 GET /v1/admin/auth/me', () => {
    it('me 返回当前管理员信息', async () => {
      const res = await request(server)
        .get('/v1/admin/auth/me')
        .set('authorization', `Bearer ${rootJwt}`)
        .expect(200);
      expect(res.body.data).toMatchObject({ username: ROOT.username, role: 'admin' });
    });

    it('无凭据 / 伪造 JWT → 401', async () => {
      await request(server).get('/v1/admin/auth/me').set('x-admin-token', 'wrong').expect(401);
      await request(server)
        .get('/v1/admin/auth/me')
        .set('authorization', 'Bearer not-a-jwt')
        .expect(401);
    });

    it('账号禁用后已签发 JWT 即刻失效 → 401', async () => {
      const login = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: REVIEWER.username, password: REVIEWER.password })
        .expect(200);
      const jwt = login.body.data.accessToken as string;
      const acc = store.findAdminByUsername(REVIEWER.username)!;
      acc.disabled = true;
      await request(server)
        .get('/v1/admin/auth/me')
        .set('authorization', `Bearer ${jwt}`)
        .expect(401);
      acc.disabled = false; // 还原，供后续角色门用例使用
    });
  });

  describe('角色门（@AdminRole）', () => {
    beforeAll(async () => {
      const res = await request(server).post('/v1/admin/auth/login').send(REVIEWER).expect(200);
      reviewerJwt = res.body.data.accessToken;
    });

    it('reviewer 调食物候选/打卡审核 → 200', async () => {
      const auth = { authorization: `Bearer ${reviewerJwt}` };
      await request(server).get('/v1/admin/food-candidates').set(auth).expect(200);
      await request(server).get('/v1/admin/posts').set(auth).expect(200);
    });
  });

  describe('x-admin-token 兜底兼容（过渡方案，视为 admin）', () => {
    const authHeader = { 'x-admin-token': ADMIN_TOKEN };

    it('审核端点可用', async () => {
      await request(server).get('/v1/admin/food-candidates').set(authHeader).expect(200);
      await request(server).get('/v1/admin/posts').set(authHeader).expect(200);
    });

    it('me 返回 token 兜底身份（role=admin）', async () => {
      const res = await request(server).get('/v1/admin/auth/me').set(authHeader).expect(200);
      expect(res.body.data).toMatchObject({ id: null, username: 'token', role: 'admin' });
    });

    it('错 token → 401', async () => {
      await request(server)
        .get('/v1/admin/food-candidates')
        .set('x-admin-token', 'wrong')
        .expect(401);
    });
  });

  describe('POST /v1/admin/auth/password（修改自己的密码）', () => {
    const NEW_PASSWORD = 'new-pass-5678';

    it('改密成功：旧密码失效、新密码可登录，已签发 JWT 仍有效', async () => {
      const login = await request(server).post('/v1/admin/auth/login').send(PWADMIN).expect(200);
      const jwt = login.body.data.accessToken as string;

      const res = await request(server)
        .post('/v1/admin/auth/password')
        .set('authorization', `Bearer ${jwt}`)
        .send({ oldPassword: PWADMIN.password, newPassword: NEW_PASSWORD })
        .expect(200);
      expect(res.body.data).toEqual({ changed: true });

      // JWT 无状态：改密后旧令牌在有效期内仍可用
      await request(server)
        .get('/v1/admin/auth/me')
        .set('authorization', `Bearer ${jwt}`)
        .expect(200);
      // 旧密码已失效，新密码可登录
      await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: PWADMIN.username, password: PWADMIN.password })
        .expect(401);
      await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: PWADMIN.username, password: NEW_PASSWORD })
        .expect(200);
    });

    it('旧密码错误 → 401 AUTH_TOKEN_INVALID，密码不变', async () => {
      const login = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: PWADMIN2.username, password: PWADMIN2.password })
        .expect(200);
      const jwt = login.body.data.accessToken as string;
      const before = store.findAdminByUsername(PWADMIN2.username)!.passwordHash;

      const res = await request(server)
        .post('/v1/admin/auth/password')
        .set('authorization', `Bearer ${jwt}`)
        .send({ oldPassword: 'wrong-old-pass', newPassword: 'another-pass-99' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_TOKEN_INVALID');
      expect(store.findAdminByUsername(PWADMIN2.username)!.passwordHash).toBe(before);
    });

    it('弱密码（<10 位）→ 400 VALIDATION_ERROR', async () => {
      const login = await request(server)
        .post('/v1/admin/auth/login')
        .send({ username: PWADMIN3.username, password: PWADMIN3.password })
        .expect(200);
      const res = await request(server)
        .post('/v1/admin/auth/password')
        .set('authorization', `Bearer ${login.body.data.accessToken}`)
        .send({ oldPassword: PWADMIN3.password, newPassword: 'short' })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('x-admin-token 兜底身份 → 403 ADMIN_TOKEN_NO_PASSWORD', async () => {
      const res = await request(server)
        .post('/v1/admin/auth/password')
        .set('x-admin-token', ADMIN_TOKEN)
        .send({ oldPassword: 'whatever', newPassword: 'new-pass-0000' })
        .expect(403);
      expect(res.body.error.code).toBe('ADMIN_TOKEN_NO_PASSWORD');
    });

    it('未登录 → 401', async () => {
      await request(server)
        .post('/v1/admin/auth/password')
        .send({ oldPassword: 'whatever', newPassword: 'new-pass-0000' })
        .expect(401);
    });
  });
});

import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';

const ADMIN_TOKEN = 'test-admin-token';
const ROOT = { username: 'root', password: 'root-pass-123' };
const REVIEWER = { username: 'reviewer1', password: 'rev-pass-123' };

/**
 * e2e：管理员账号体系（/v1/admin/auth/* + AdminAuthGuard + @AdminRole 角色门）。
 * 覆盖：种子账号创建、登录成功/错误密码/disabled 拒登/限流 5 次每分钟、
 * JWT 鉴权与禁用即刻失效、角色门（reviewer 调 config 403 / 调审核 200）、
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
    process.env.LLM_PROVIDER = 'stub'; // 盖掉 .env，保证初始态确定

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
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
    delete process.env.ADMIN_USERNAME;
    delete process.env.ADMIN_PASSWORD;
    delete process.env.LLM_PROVIDER;
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

    it('reviewer 调 config（GET/PUT/llm/test）→ 403 FORBIDDEN', async () => {
      const auth = { authorization: `Bearer ${reviewerJwt}` };
      const res = await request(server).get('/v1/admin/config').set(auth).expect(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
      await request(server)
        .put('/v1/admin/config/llm')
        .set(auth)
        .send({ provider: 'stub' })
        .expect(403);
      await request(server).post('/v1/admin/config/llm/test').set(auth).expect(403);
    });

    it('reviewer 调食物候选/打卡审核 → 200', async () => {
      const auth = { authorization: `Bearer ${reviewerJwt}` };
      await request(server).get('/v1/admin/food-candidates').set(auth).expect(200);
      await request(server).get('/v1/admin/posts').set(auth).expect(200);
    });

    it('admin 调 config → 200', async () => {
      await request(server)
        .get('/v1/admin/config')
        .set('authorization', `Bearer ${rootJwt}`)
        .expect(200);
    });
  });

  describe('x-admin-token 兜底兼容（过渡方案，视为 admin）', () => {
    const authHeader = { 'x-admin-token': ADMIN_TOKEN };

    it('config / 审核端点均可用', async () => {
      await request(server).get('/v1/admin/config').set(authHeader).expect(200);
      await request(server).get('/v1/admin/food-candidates').set(authHeader).expect(200);
      await request(server).get('/v1/admin/posts').set(authHeader).expect(200);
    });

    it('me 返回 token 兜底身份（role=admin）', async () => {
      const res = await request(server).get('/v1/admin/auth/me').set(authHeader).expect(200);
      expect(res.body.data).toMatchObject({ id: null, username: 'token', role: 'admin' });
    });

    it('错 token → 401', async () => {
      await request(server).get('/v1/admin/config').set('x-admin-token', 'wrong').expect(401);
    });
  });
});

import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';

const ADMIN = 'test-admin-token';

/**
 * e2e：管理端注册用户列表（/v1/admin/users，x-admin-token）。
 * 鉴权（缺/错 token → 401）、页码分页、手机号脱敏（明文不出响应）、
 * keyword 三字段模糊匹配（username/phone/nickname）、tombstone 用户排除。
 */
describe('Admin users list (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let store: DataStore;

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
    store = app.get(DataStore);
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
  });

  let seq = 0;
  function nextPhone(): string {
    seq += 1;
    return `+8613877${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-admin-users', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const asAdmin = (r: request.Test) => r.set('x-admin-token', ADMIN);

  async function listUsers(qs = ''): Promise<{
    items: Array<Record<string, unknown>>;
    total: number;
    page: number;
    pageSize: number;
  }> {
    const res = await asAdmin(request(server).get(`/v1/admin/users${qs}`)).expect(200);
    return res.body.data as {
      items: Array<Record<string, unknown>>;
      total: number;
      page: number;
      pageSize: number;
    };
  }

  it('token 保护：缺 header / 错 token → 401', async () => {
    await request(server).get('/v1/admin/users').expect(401);
    await request(server).get('/v1/admin/users').set('x-admin-token', 'wrong').expect(401);
  });

  it('列表：字段齐全 + 手机号脱敏（明文不出现在响应）', async () => {
    const phone = nextPhone();
    const token = await login(phone);
    await request(server).patch('/v1/users/me').set('Authorization', `Bearer ${token}`).send({
      nickname: '管理员可见昵称',
      goal: 'fat_loss',
    });

    const { items } = await listUsers();
    const row = items.find((u) => u.nickname === '管理员可见昵称');
    expect(row).toBeDefined();
    expect(row).toMatchObject({
      username: null,
      nickname: '管理员可见昵称',
      goal: 'fat_loss',
      onboardingStatus: 'none',
      deletionStatus: null,
    });
    expect(typeof row!.id).toBe('string');
    expect(typeof row!.createdAt).toBe('string');
    // 脱敏：138****xxxx 形态，完整明文（含国家码）不出现
    expect(row!.phone).toMatch(/^138\*\*\*\*\d{4}$/);
    expect(row!.phone).not.toBe(phone);
    expect(JSON.stringify(items)).not.toContain(phone.replace('+86', ''));
  });

  it('分页：page/pageSize 切片 + total；非法 page/pageSize → 400', async () => {
    // 本用例独占 keyword 前缀，避开其他用例的用户
    const phones = [nextPhone(), nextPhone(), nextPhone()];
    for (const p of phones) await login(p);

    const page1 = await listUsers('?keyword=13877&page=1&pageSize=2');
    expect(page1.items.length).toBeGreaterThanOrEqual(2);
    expect(page1.page).toBe(1);
    expect(page1.pageSize).toBe(2);
    expect(page1.total).toBeGreaterThanOrEqual(3);

    const page2 = await listUsers('?keyword=13877&page=2&pageSize=2');
    expect(page2.page).toBe(2);
    expect(page2.items.length).toBeGreaterThanOrEqual(1);
    // 两页不重叠
    const ids1 = new Set(page1.items.map((u) => u.id));
    for (const u of page2.items) expect(ids1.has(u.id)).toBe(false);

    await asAdmin(request(server).get('/v1/admin/users?page=0')).expect(400);
    await asAdmin(request(server).get('/v1/admin/users?pageSize=abc')).expect(400);
  });

  it('keyword：phone/nickname/username 模糊匹配；大小写不敏感；无命中返回空', async () => {
    const phone = nextPhone(); // +8613877000xxx
    const token = await login(phone);
    await request(server)
      .patch('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ nickname: 'Unique昵称Zephyr' });

    // phone 子串命中
    const byPhone = await listUsers(`?keyword=${encodeURIComponent(phone.slice(-6))}`);
    expect(byPhone.items.some((u) => u.nickname === 'Unique昵称Zephyr')).toBe(true);
    // nickname 子串 + 大小写不敏感
    const byNick = await listUsers('?keyword=zephyr');
    expect(byNick.items.some((u) => u.nickname === 'Unique昵称Zephyr')).toBe(true);
    // username（账号密码注册用户，小写归一化存储）
    await request(server)
      .post('/v1/auth/register')
      .send({ username: 'AdminListUser01', password: 'passw0rd1' })
      .expect(201); // 用户名小写归一化存储
    const byName = await listUsers('?keyword=ADMINLISTUSER');
    expect(byName.items.some((u) => u.username === 'adminlistuser01')).toBe(true);
    // 无命中
    const none = await listUsers('?keyword=zzz-not-exist-zzz');
    expect(none.items).toHaveLength(0);
    expect(none.total).toBe(0);
  });

  it('tombstone（deletedAt）用户不出现在列表', async () => {
    const phone = nextPhone();
    const token = await login(phone);
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    const userId = me.body.data.user.id as string;
    store.users.get(userId)!.deletedAt = new Date(); // 直接置 tombstone 构造夹具

    const { items } = await listUsers();
    expect(items.some((u) => u.id === userId)).toBe(false);
  });
});

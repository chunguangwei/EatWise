import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcryptjs';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';

const ADMIN = 'test-admin-token';
const REVIEWER = { username: 'reviewer-role-gate', password: 'rev-pass-123' };

/**
 * 移动端审批中心（/v1/moderation/food-candidates，用户 JWT + User.role=admin）
 * 与管理台设角色（PATCH /v1/admin/users/:id/role）e2e：
 * 匿名 401 / 普通用户 403 / admin 用户可查可审（含驳回级联清理 + reviewedBy 留痕）。
 */
describe('Mobile moderation & user role (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    // reviewer 角色管理员账号（管理端暂无账号管理接口，直接落库〔假设〕）
    app.get(DataStore).createAdminUser({
      username: REVIEWER.username,
      passwordHash: bcrypt.hashSync(REVIEWER.password, 10),
      role: 'reviewer',
      disabled: false,
    });
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

  let uuidSeq = 0;
  function nextUuid(): string {
    uuidSeq += 1;
    return `c3d4e5f6-${String(uuidSeq).padStart(4, '0')}-4111-8111-222222222222`;
  }

  async function login(phone: string): Promise<{ token: string; userId: string }> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-moderation', platform: 'ios' } })
      .expect(200);
    const token = res.body.data.accessToken as string;
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    return { token, userId: me.body.data.user.id as string };
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  it('匿名 → 401；普通用户 → 403（列表与审核都拦）', async () => {
    await request(server).get('/v1/moderation/food-candidates').expect(401);

    const user = await login(nextPhone());
    await request(server)
      .get('/v1/moderation/food-candidates')
      .set(auth(user.token))
      .expect(403);
    await request(server)
      .post('/v1/moderation/food-candidates/fc_x/review')
      .set(auth(user.token))
      .send({ action: 'approve' })
      .expect(403);
  });

  it('PATCH /v1/admin/users/:id/role：x-admin-token 可设；非法 role 400；不存在 404；无凭据 401', async () => {
    const user = await login(nextPhone());

    await request(server)
      .patch(`/v1/admin/users/${user.userId}/role`)
      .send({ role: 'admin' })
      .expect(401); // AdminAuthGuard：无 JWT 且无 token

    await request(server)
      .patch(`/v1/admin/users/${user.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'superuser' })
      .expect(400);

    await request(server)
      .patch('/v1/admin/users/u_not_exist/role')
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(404);

    const res = await request(server)
      .patch(`/v1/admin/users/${user.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);
    expect(res.body.data.role).toBe('admin');

    // 幂等：重复设置同值仍 200
    const again = await request(server)
      .patch(`/v1/admin/users/${user.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);
    expect(again.body.data.role).toBe('admin');

    // reviewer 角色管理员 JWT 不可设角色（403，仅 admin）
    const reviewerLogin = await request(server)
      .post('/v1/admin/auth/login')
      .send(REVIEWER)
      .expect(200);
    await request(server)
      .patch(`/v1/admin/users/${user.userId}/role`)
      .set('Authorization', `Bearer ${reviewerLogin.body.data.accessToken}`)
      .send({ role: 'user' })
      .expect(403);

    // 列表视图带 role
    const list = await request(server)
      .get('/v1/admin/users')
      .set('x-admin-token', ADMIN)
      .expect(200);
    const row = (list.body.data.items as Array<{ id: string; role: string }>).find(
      (u) => u.id === user.userId,
    );
    expect(row?.role).toBe('admin');
  });

  it('admin 用户移动端可查可审：列表 pending → approve（留痕 reviewedBy=用户 id）→ 共享库可见', async () => {
    const owner = await login(nextPhone());
    const admin = await login(nextPhone());
    await request(server)
      .patch(`/v1/admin/users/${admin.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);

    // 普通用户贡献候选
    const custom = await request(server)
      .post('/v1/foods/custom')
      .set(auth(owner.token))
      .send({
        clientRequestId: nextUuid(),
        nameZh: '移动审批羊肉泡馍',
        per100g: { kcal: 150, proteinG: 9, carbG: 18, fatG: 5 },
        source: 'manual',
      })
      .expect(200);
    const contributed = await request(server)
      .post(`/v1/foods/custom/${custom.body.data.id}/contribute`)
      .set(auth(owner.token))
      .send({ clientRequestId: nextUuid() })
      .expect(200);
    const candidateId = contributed.body.data.id as string;

    // admin 用户移动端拉队列 → 审批
    const queue = await request(server)
      .get('/v1/moderation/food-candidates?status=pending')
      .set(auth(admin.token))
      .expect(200);
    const item = (queue.body.data.items as Array<{ id: string }>).find((c) => c.id === candidateId);
    expect(item).toBeDefined();

    const reviewed = await request(server)
      .post(`/v1/moderation/food-candidates/${candidateId}/review`)
      .set(auth(admin.token))
      .send({ action: 'approve' })
      .expect(200);
    expect(reviewed.body.data.status).toBe('approved');
    expect(reviewed.body.data.reviewedBy).toBe(admin.userId);

    // 晋升后其他用户搜索可见
    const stranger = await login(nextPhone());
    const search = await request(server)
      .get('/v1/foods/search?q=移动审批羊肉泡馍')
      .set(auth(stranger.token))
      .expect(200);
    expect(
      (search.body.data.items as Array<{ id: string }>).find((f) => f.id === custom.body.data.id),
    ).toBeDefined();
  });

  it('admin 用户移动端驳回：级联清理记录 + reviewedBy 留痕 + 重复驳回幂等', async () => {
    const owner = await login(nextPhone());
    const admin = await login(nextPhone());
    await request(server)
      .patch(`/v1/admin/users/${admin.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);

    // 乐观入账：自定义食物 + 记录上行
    const custom = await request(server)
      .post('/v1/foods/custom')
      .set(auth(owner.token))
      .send({
        clientRequestId: nextUuid(),
        nameZh: '移动驳回擀面皮',
        per100g: { kcal: 170, proteinG: 5, carbG: 25, fatG: 6 },
        source: 'manual',
      })
      .expect(200);
    const foodId = custom.body.data.id as string;
    const pushed = await request(server)
      .post('/v1/sync/push')
      .set(auth(owner.token))
      .send({
        ops: [
          {
            clientRequestId: nextUuid(),
            entity: 'foodEntry',
            op: 'create',
            payload: {
              eatenAt: '2026-09-19T04:10:00.000Z',
              foodId,
              grams: 200,
              inputMethod: 'manual',
            },
          },
        ],
      })
      .expect(200);
    expect(pushed.body.data.results[0].status).toBe('applied');
    const entryId = pushed.body.data.results[0].serverEntry.id as string;

    const contributed = await request(server)
      .post(`/v1/foods/custom/${foodId}/contribute`)
      .set(auth(owner.token))
      .send({ clientRequestId: nextUuid() })
      .expect(200);
    const candidateId = contributed.body.data.id as string;

    const rejected = await request(server)
      .post(`/v1/moderation/food-candidates/${candidateId}/review`)
      .set(auth(admin.token))
      .send({ action: 'reject', reason: '营养数据存疑' })
      .expect(200);
    expect(rejected.body.data.status).toBe('rejected');
    expect(rejected.body.data.reviewedBy).toBe(admin.userId);

    // 级联清理：sync/pull 下行 tombstone
    const pull = await request(server)
      .get('/v1/sync/pull')
      .set(auth(owner.token))
      .expect(200);
    const tombstone = (pull.body.data.changes as Array<Record<string, unknown>>).find(
      (c) => (c.tombstone as { id?: string } | undefined)?.id === entryId,
    );
    expect(tombstone).toBeDefined();

    // 重复驳回幂等 200
    const again = await request(server)
      .post(`/v1/moderation/food-candidates/${candidateId}/review`)
      .set(auth(admin.token))
      .send({ action: 'reject', reason: '重复驳回' })
      .expect(200);
    expect(again.body.data.status).toBe('rejected');
    expect(again.body.data.reason).toBe('营养数据存疑');
  });

  it('降级回 user 后立即失去审批权限（403）', async () => {
    const admin = await login(nextPhone());
    await request(server)
      .patch(`/v1/admin/users/${admin.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);
    await request(server)
      .get('/v1/moderation/food-candidates')
      .set(auth(admin.token))
      .expect(200);

    await request(server)
      .patch(`/v1/admin/users/${admin.userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'user' })
      .expect(200);
    await request(server)
      .get('/v1/moderation/food-candidates')
      .set(auth(admin.token))
      .expect(403);
  });
});

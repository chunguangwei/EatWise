import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';

const ADMIN = 'test-admin-token';

/**
 * e2e：管理端打卡审核队列（/v1/admin/posts，x-admin-token）。
 * 队列四态（pending/approved/rejected/reported）筛选 → 审核决定（上架/下架/恢复）
 * → 举报即下架进 reported 队列 → approve 恢复上架；token 保护与未配置关闭。
 */
describe('Admin posts review (e2e)', () => {
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
    return `+8613955${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-admin-posts', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  async function createPost(token: string, text: string): Promise<string> {
    const res = await request(server)
      .post('/v1/posts')
      .set(auth(token))
      .send({ clientRequestId: crypto.randomUUID(), text })
      .expect(200);
    return res.body.data.id as string;
  }

  /** 开放模式下发帖即 approved；pending 夹具直接改库存状态构造。 */
  function markPending(postId: string) {
    store.posts.get(postId)!.auditStatus = 'pending';
  }

  async function listIds(status: string): Promise<Array<Record<string, unknown>>> {
    const res = await request(server)
      .get(`/v1/admin/posts?status=${status}`)
      .set('x-admin-token', ADMIN)
      .expect(200);
    return res.body.data.items as Array<Record<string, unknown>>;
  }

  async function feedHas(viewer: string, postId: string): Promise<boolean> {
    const res = await request(server).get('/v1/posts/feed?limit=50').set(auth(viewer)).expect(200);
    return (res.body.data.items as Array<{ id: string }>).some((i) => i.id === postId);
  }

  it('token 保护：缺 header / 错 token → 401', async () => {
    await request(server).get('/v1/admin/posts').expect(401);
    await request(server).get('/v1/admin/posts').set('x-admin-token', 'wrong').expect(401);
    await request(server)
      .post('/v1/admin/posts/p_x/review')
      .set('x-admin-token', 'wrong')
      .send({ action: 'approve' })
      .expect(401);
  });

  it('队列四态：pending/approved/rejected/reported 各自筛选命中，非法 status → 400', async () => {
    const author = await login(nextPhone());
    const reporter = await login(nextPhone());
    const pendingId = await createPost(author, '队列待审：顺便代购一点');
    markPending(pendingId);
    const approvedId = await createPost(author, '队列已上架打卡');
    const reportedId = await createPost(author, '队列将被举报的打卡');
    await request(server)
      .post(`/v1/posts/${reportedId}/report`)
      .set(auth(reporter))
      .send({ reason: '广告' })
      .expect(200);
    const rejectedId = await createPost(author, '队列普通下架打卡');
    await request(server)
      .post(`/v1/admin/posts/${rejectedId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'reject', reason: '与主题无关' })
      .expect(200);

    const ids = (list: Array<Record<string, unknown>>) => list.map((i) => i.id as string);
    expect(ids(await listIds('pending'))).toContain(pendingId);
    expect(ids(await listIds('approved'))).toContain(approvedId);
    expect(ids(await listIds('approved'))).not.toContain(reportedId);

    const rejected = await listIds('rejected');
    expect(ids(rejected)).toContain(rejectedId);
    expect(ids(rejected)).not.toContain(reportedId); // 被举报的归入 reported，不算普通 rejected

    const reported = await listIds('reported');
    expect(ids(reported)).toContain(reportedId);
    const reportedItem = reported.find((i) => i.id === reportedId) as {
      reportCount: number;
      reportedAt: string | null;
      auditStatus: string;
      author: { id: string };
    };
    expect(reportedItem.auditStatus).toBe('rejected');
    expect(reportedItem.reportCount).toBe(1);
    expect(reportedItem.reportedAt).toBeTruthy();
    expect(reportedItem.author.id).toBeTruthy();

    await request(server)
      .get('/v1/admin/posts?status=bogus')
      .set('x-admin-token', ADMIN)
      .expect(400);
  });

  it('游标分页：limit 生效，nextCursor 翻页不重复', async () => {
    const author = await login(nextPhone());
    for (let i = 0; i < 3; i++) {
      markPending(await createPost(author, `管理端分页待审 ${i} 代购`));
    }
    const page1 = await request(server)
      .get('/v1/admin/posts?status=pending&limit=2')
      .set('x-admin-token', ADMIN)
      .expect(200);
    expect(page1.body.data.items.length).toBe(2);
    expect(page1.body.data.pageInfo.hasMore).toBe(true);
    const page2 = await request(server)
      .get(
        `/v1/admin/posts?status=pending&limit=2&cursor=${encodeURIComponent(
          page1.body.data.pageInfo.nextCursor as string,
        )}`,
      )
      .set('x-admin-token', ADMIN)
      .expect(200);
    const ids1 = page1.body.data.items.map((i: { id: string }) => i.id) as string[];
    const ids2 = page2.body.data.items.map((i: { id: string }) => i.id) as string[];
    expect(ids2.some((id) => ids1.includes(id))).toBe(false);
  });

  it('approve pending → approved（version+1，他人流可见）；重复 approve → 409', async () => {
    const author = await login(nextPhone());
    const viewer = await login(nextPhone());
    const postId = await createPost(author, '待审恢复：兼职心得分享');
    markPending(postId);
    expect(await feedHas(viewer, postId)).toBe(false);

    const res = await request(server)
      .post(`/v1/admin/posts/${postId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(200);
    expect(res.body.data.auditStatus).toBe('approved');
    expect(res.body.data.version).toBe(2);
    expect(await feedHas(viewer, postId)).toBe(true);

    await request(server)
      .post(`/v1/admin/posts/${postId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(409);
  });

  it('reject pending（附原因）→ rejected 下架，作者可见双语原因；reject approved 同样下架', async () => {
    const author = await login(nextPhone());
    const viewer = await login(nextPhone());
    const pendingId = await createPost(author, '待审下架：刷单返利了解一下');
    markPending(pendingId);
    const res = await request(server)
      .post(`/v1/admin/posts/${pendingId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'reject', reason: '疑似引流' })
      .expect(200);
    expect(res.body.data.auditStatus).toBe('rejected');
    expect(res.body.data.auditReason.zh).toBe('疑似引流');
    expect(res.body.data.version).toBe(2);

    const own = await request(server).get(`/v1/posts/${pendingId}`).set(auth(author)).expect(200);
    expect(own.body.data.auditReason.zh).toBe('疑似引流');

    // approved 帖也可被管理端下架（他人流消失）
    const approvedId = await createPost(author, '先上架后下架的打卡');
    expect(await feedHas(viewer, approvedId)).toBe(true);
    await request(server)
      .post(`/v1/admin/posts/${approvedId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'reject', reason: '复核不通过' })
      .expect(200);
    expect(await feedHas(viewer, approvedId)).toBe(false);
  });

  it('举报即下架进 reported 队列 → 管理端 approve 恢复上架（出队列、他人流可见）', async () => {
    const author = await login(nextPhone());
    const reporter = await login(nextPhone());
    const postId = await createPost(author, '被误举报的正常打卡');
    await request(server)
      .post(`/v1/posts/${postId}/report`)
      .set(auth(reporter))
      .send({ reason: '误报测试' })
      .expect(200);
    expect(await feedHas(reporter, postId)).toBe(false);
    expect((await listIds('reported')).map((i) => i.id)).toContain(postId);

    const res = await request(server)
      .post(`/v1/admin/posts/${postId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(200);
    expect(res.body.data.auditStatus).toBe('approved');
    expect(res.body.data.reportCount).toBe(1); // 举报计数保留溯源
    expect(await feedHas(reporter, postId)).toBe(true);
    expect((await listIds('reported')).map((i) => i.id)).not.toContain(postId);
    expect((await listIds('approved')).map((i) => i.id)).toContain(postId);
  });

  it('审核不存在的帖 → 404；非法 action → 400', async () => {
    await request(server)
      .post('/v1/admin/posts/p_notexist/review')
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(404);
    const author = await login(nextPhone());
    const postId = await createPost(author, '非法 action 测试');
    await request(server)
      .post(`/v1/admin/posts/${postId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'bogus' })
      .expect(400);
  });
});

/** 〔假设〕ADMIN_TOKEN 未配置时管理端点整体关闭（404，不暴露存在性） */
describe('Admin posts endpoints without ADMIN_TOKEN (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    delete process.env.ADMIN_TOKEN;
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

  it('未配置 ADMIN_TOKEN → 打卡审核端点 404', async () => {
    await request(server).get('/v1/admin/posts').set('x-admin-token', 'whatever').expect(404);
    await request(server)
      .post('/v1/admin/posts/p_x/review')
      .set('x-admin-token', 'whatever')
      .send({ action: 'approve' })
      .expect(404);
  });
});

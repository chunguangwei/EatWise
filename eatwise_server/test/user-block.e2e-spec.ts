import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：UGC 屏蔽用户（App Store 条例 1.2）——屏蔽/解除/列表 + 信息流过滤 + 互动拦截 */
describe('User blocks (e2e)', () => {
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

  let seq = 400;
  function nextPhone(): string {
    seq += 1;
    return `+8613988${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<{ token: string; userId: string }> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-block', platform: 'ios' } })
      .expect(200);
    return { token: res.body.data.accessToken as string, userId: res.body.data.user.id as string };
  }

  it('屏蔽 → 信息流过滤 + 详情/互动 404 + 列表 + 解除恢复', async () => {
    const author = await login(nextPhone());
    const viewer = await login(nextPhone());

    const created = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${author.token}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '屏蔽测试打卡' })
      .expect(200);
    const postId = created.body.data.id as string;
    expect(created.body.data.author.id).toBe(author.userId);

    // 屏蔽前：可见、可点赞
    await request(server)
      .post(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);

    // 不能屏蔽自己 400
    await request(server)
      .post(`/v1/users/${viewer.userId}/block`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(400);

    // 屏蔽（幂等）
    await request(server)
      .post(`/v1/users/${author.userId}/block`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    await request(server)
      .post(`/v1/users/${author.userId}/block`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);

    // 列表含被屏蔽者
    const blocks = await request(server)
      .get('/v1/users/me/blocks')
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    expect(
      (blocks.body.data.items as Array<{ userId: string }>).some((b) => b.userId === author.userId),
    ).toBe(true);

    // 信息流不再出现对方帖；详情 404；互动 404
    const feed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    expect((feed.body.data.items as Array<{ id: string }>).some((i) => i.id === postId)).toBe(
      false,
    );
    await request(server)
      .get(`/v1/posts/${postId}`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(404);
    await request(server)
      .post(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(404);
    // 被屏蔽者也不能给屏蔽方的帖点赞（反向拦截）
    const viewerPost = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${viewer.token}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '屏蔽方自己的打卡' })
      .expect(200);
    await request(server)
      .post(`/v1/posts/${viewerPost.body.data.id}/like`)
      .set('Authorization', `Bearer ${author.token}`)
      .expect(404);
    // 单向过滤：屏蔽方的流不受「被屏蔽者视角」影响——作者的流仍正常
    const authorFeed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${author.token}`)
      .expect(200);
    expect((authorFeed.body.data.items as Array<{ id: string }>).some((i) => i.id === postId)).toBe(
      true,
    );

    // 解除（幂等）→ 信息流恢复
    await request(server)
      .delete(`/v1/users/${author.userId}/block`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    await request(server)
      .delete(`/v1/users/${author.userId}/block`)
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    const restored = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${viewer.token}`)
      .expect(200);
    expect((restored.body.data.items as Array<{ id: string }>).some((i) => i.id === postId)).toBe(
      true,
    );
  });

  it('匿名请求 401', async () => {
    await request(server).get('/v1/users/me/blocks').expect(401);
    await request(server).post('/v1/users/someone/block').expect(401);
  });
});

import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：社区打卡 C1–C7（先审后发三态 / 流可见性 / 点赞幂等 / 举报下架） */
describe('Social posts (e2e)', () => {
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
    return `+8613977${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-social', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  it('C1 发布（机审通过 → approved）→ C2 他人可见；点赞幂等；删除后点赞 410', async () => {
    const author = await login(nextPhone());
    const viewer = await login(nextPhone());

    const created = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${author}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '第一天 16:8，完成！' })
      .expect(200);
    expect(created.body.data.auditStatus).toBe('approved');
    expect(created.body.data.streakDaysAtPost).toBe(0);
    const postId = created.body.data.id as string;

    // C2 他人可见 approved 帖
    const feed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${viewer}`)
      .expect(200);
    const item = feed.body.data.items.find((i: { id: string }) => i.id === postId);
    expect(item).toBeTruthy();
    expect(item.likedByMe).toBe(false);

    // C5 点赞幂等
    await request(server)
      .post(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer}`)
      .expect(200);
    const relike = await request(server)
      .post(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer}`)
      .expect(200);
    expect(relike.body.data.likeCount).toBe(1);

    // C6 取消点赞幂等
    const unlike = await request(server)
      .delete(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer}`)
      .expect(200);
    expect(unlike.body.data.likeCount).toBe(0);
    expect(unlike.body.data.likedByMe).toBe(false);

    // C4 删除 → 再点赞 410 RESOURCE_GONE
    await request(server)
      .delete(`/v1/posts/${postId}`)
      .set('Authorization', `Bearer ${author}`)
      .expect(200);
    const gone = await request(server)
      .post(`/v1/posts/${postId}/like`)
      .set('Authorization', `Bearer ${viewer}`)
      .expect(410);
    expect(gone.body.error.code).toBe('RESOURCE_GONE');
  });

  it('C1 违规内容 → 400 POST_CONTENT_REJECTED（Accept-Language 双语）', async () => {
    const token = await login(nextPhone());
    const zh = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '赌博广告' })
      .expect(400);
    expect(zh.body.error.code).toBe('POST_CONTENT_REJECTED');
    expect(zh.body.error.message).toBe('内容未通过审核，无法发布');
    expect(zh.body.error.details.reason.zh).toContain('违规');

    const en = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${token}`)
      .set('Accept-Language', 'en')
      .send({ clientRequestId: crypto.randomUUID(), text: 'come to casino' })
      .expect(400);
    expect(en.body.error.message).toBe('Content did not pass review and cannot be published');
  });

  it('C1 疑似内容 → pending 转人工：本人流可见，他人流不可见', async () => {
    const author = await login(nextPhone());
    const viewer = await login(nextPhone());
    const created = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${author}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '打卡，顺便代购一下' })
      .expect(200);
    expect(created.body.data.auditStatus).toBe('pending');
    const postId = created.body.data.id as string;

    const ownFeed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${author}`)
      .expect(200);
    expect(ownFeed.body.data.items.some((i: { id: string }) => i.id === postId)).toBe(true);

    const otherFeed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${viewer}`)
      .expect(200);
    expect(otherFeed.body.data.items.some((i: { id: string }) => i.id === postId)).toBe(false);

    await request(server)
      .get(`/v1/posts/${postId}`)
      .set('Authorization', `Bearer ${viewer}`)
      .expect(404);
  });

  it('C7 举报 → 下架（他人流不可见）且幂等', async () => {
    const author = await login(nextPhone());
    const reporter = await login(nextPhone());
    const created = await request(server)
      .post('/v1/posts')
      .set('Authorization', `Bearer ${author}`)
      .send({ clientRequestId: crypto.randomUUID(), text: '普通打卡内容' })
      .expect(200);
    const postId = created.body.data.id as string;

    await request(server)
      .post(`/v1/posts/${postId}/report`)
      .set('Authorization', `Bearer ${reporter}`)
      .send({ reason: '垃圾信息' })
      .expect(200);
    await request(server)
      .post(`/v1/posts/${postId}/report`)
      .set('Authorization', `Bearer ${reporter}`)
      .send({ reason: '垃圾信息' })
      .expect(200); // 幂等

    const feed = await request(server)
      .get('/v1/posts/feed')
      .set('Authorization', `Bearer ${reporter}`)
      .expect(200);
    expect(feed.body.data.items.some((i: { id: string }) => i.id === postId)).toBe(false);

    // 作者仍可见（rejected + 双语原因）
    const own = await request(server)
      .get(`/v1/posts/${postId}`)
      .set('Authorization', `Bearer ${author}`)
      .expect(200);
    expect(own.body.data.auditStatus).toBe('rejected');
    expect(own.body.data.auditReason.en).toBeTruthy();
  });

  it('C2 游标分页：limit 生效，nextCursor 翻页', async () => {
    const author = await login(nextPhone());
    for (let i = 0; i < 3; i++) {
      await request(server)
        .post('/v1/posts')
        .set('Authorization', `Bearer ${author}`)
        .send({ clientRequestId: crypto.randomUUID(), text: `分页测试 ${i}` })
        .expect(200);
    }
    const page1 = await request(server)
      .get('/v1/posts/feed?limit=2')
      .set('Authorization', `Bearer ${author}`)
      .expect(200);
    expect(page1.body.data.items.length).toBe(2);
    expect(page1.body.data.pageInfo.hasMore).toBe(true);
    const page2 = await request(server)
      .get(
        `/v1/posts/feed?limit=2&cursor=${encodeURIComponent(page1.body.data.pageInfo.nextCursor)}`,
      )
      .set('Authorization', `Bearer ${author}`)
      .expect(200);
    expect(page2.body.data.items.length).toBe(1);
    expect(page2.body.data.pageInfo.hasMore).toBe(false);
    const ids = [
      ...page1.body.data.items.map((i: { id: string }) => i.id),
      ...page2.body.data.items.map((i: { id: string }) => i.id),
    ];
    expect(new Set(ids).size).toBe(3);
  });
});

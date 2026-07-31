import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：LLM 估算端点（stub 降级/校验/限流）+ 自定义食物（幂等/搜索合并/可见性隔离） */
describe('Foods estimate & custom (e2e)', () => {
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
  function nextPhone(): string {
    seq += 1;
    return `+8613911${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-food', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  const customBody = {
    clientRequestId: 'a1b2c3d4-1111-4111-8111-111111111111',
    nameZh: '外婆红烧肉',
    nameEn: 'Grandma Braised Pork',
    aliasesZh: ['红烧肉(外婆版)'],
    aliasesEn: ['hong shao rou'],
    per100g: { kcal: 320, proteinG: 12, carbG: 6, fatG: 28 },
    source: 'manual',
  };

  describe('POST /v1/foods/custom', () => {
    it('创建成功 → isCustom/source/per100g；幂等重放返回同一记录', async () => {
      const token = await login(nextPhone());
      const res = await request(server)
        .post('/v1/foods/custom')
        .set(auth(token))
        .send(customBody)
        .expect(200);
      expect(res.body.data.isCustom).toBe(true);
      expect(res.body.data.source).toBe('manual');
      expect(res.body.data.per100g).toEqual(customBody.per100g);

      const replay = await request(server)
        .post('/v1/foods/custom')
        .set(auth(token))
        .send(customBody)
        .expect(200);
      expect(replay.body.data.id).toBe(res.body.data.id);
    });

    it('同 clientRequestId 不同体 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
      const token = await login(nextPhone());
      await request(server).post('/v1/foods/custom').set(auth(token)).send(customBody).expect(200);
      const res = await request(server)
        .post('/v1/foods/custom')
        .set(auth(token))
        .send({ ...customBody, nameZh: '另一个菜' })
        .expect(409);
      expect(res.body.error.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    });

    it('校验：nameZh 超 50 字 / 营养越界 → 400 VALIDATION_ERROR', async () => {
      const token = await login(nextPhone());
      await request(server)
        .post('/v1/foods/custom')
        .set(auth(token))
        .send({
          ...customBody,
          clientRequestId: 'a1b2c3d4-2222-4111-8111-111111111111',
          nameZh: 'x'.repeat(51),
        })
        .expect(400);
      const res = await request(server)
        .post('/v1/foods/custom')
        .set(auth(token))
        .send({
          ...customBody,
          clientRequestId: 'a1b2c3d4-3333-4111-8111-111111111111',
          per100g: { kcal: 901, proteinG: 10, carbG: 10, fatG: 10 },
        })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });
  });

  describe('自定义食物搜索合并与可见性隔离', () => {
    it('创建者 K1 搜索命中自定义食物（isCustom 标注，排内置之后）；他人不可见；batch-get 隔离', async () => {
      const owner = await login(nextPhone());
      const stranger = await login(nextPhone());
      const created = await request(server)
        .post('/v1/foods/custom')
        .set(auth(owner))
        .send({
          ...customBody,
          clientRequestId: 'a1b2c3d4-4444-4111-8111-111111111111',
          nameZh: '鸡胸肉秘制做法',
        })
        .expect(200);
      const foodId = created.body.data.id as string;

      // 创建者搜索「鸡胸」：内置鸡胸肉在前，自定义在后且 isCustom=true
      const mine = await request(server)
        .get('/v1/foods/search?q=鸡胸')
        .set(auth(owner))
        .expect(200);
      const customHit = mine.body.data.items.find((i: { id: string }) => i.id === foodId);
      expect(customHit).toBeDefined();
      expect(customHit.isCustom).toBe(true);
      const builtInIdx = mine.body.data.items.findIndex(
        (i: { nameZh: string; isCustom: boolean }) => i.nameZh === '鸡胸肉' && !i.isCustom,
      );
      const customIdx = mine.body.data.items.findIndex((i: { id: string }) => i.id === foodId);
      expect(builtInIdx).toBeGreaterThanOrEqual(0);
      expect(customIdx).toBeGreaterThan(builtInIdx);

      // 他人搜索不可见
      const theirs = await request(server)
        .get('/v1/foods/search?q=鸡胸')
        .set(auth(stranger))
        .expect(200);
      expect(theirs.body.data.items.find((i: { id: string }) => i.id === foodId)).toBeUndefined();

      // batch-get：创建者可见，他人取不到
      const bg1 = await request(server)
        .post('/v1/foods/batch-get')
        .set(auth(owner))
        .send({ ids: [foodId] })
        .expect(200);
      expect(bg1.body.data.items).toHaveLength(1);
      const bg2 = await request(server)
        .post('/v1/foods/batch-get')
        .set(auth(stranger))
        .send({ ids: [foodId] })
        .expect(200);
      expect(bg2.body.data.items).toHaveLength(0);
    });
  });

  describe('POST /v1/foods/estimate', () => {
    it('未配置供应商（stub）→ 503 ESTIMATE_UNAVAILABLE（双语 message）', async () => {
      const token = await login(nextPhone());
      const res = await request(server)
        .post('/v1/foods/estimate')
        .set(auth(token))
        .send({ name: '红烧肉' })
        .expect(503);
      expect(res.body.error.code).toBe('ESTIMATE_UNAVAILABLE');
      expect(res.body.error.message).toBe('营养估算暂不可用，请手动填写');

      const en = await request(server)
        .post('/v1/foods/estimate')
        .set(auth(token))
        .set('Accept-Language', 'en')
        .send({ name: '红烧肉' })
        .expect(503);
      expect(en.body.error.message).toBe(
        'Nutrition estimate unavailable, please enter values manually',
      );
    });

    it('菜名空白 → 400 VALIDATION_ERROR；未认证 → 401', async () => {
      const token = await login(nextPhone());
      await request(server)
        .post('/v1/foods/estimate')
        .set(auth(token))
        .send({ name: '   ' })
        .expect(400);
      await request(server).post('/v1/foods/estimate').send({ name: 'x' }).expect(401);
    });

    it('限流〔假设〕每用户 10 次/分钟：第 11 次 429 RATE_LIMITED', async () => {
      const token = await login(nextPhone());
      for (let i = 0; i < 10; i++) {
        await request(server)
          .post('/v1/foods/estimate')
          .set(auth(token))
          .send({ name: `测试菜${i}` })
          .expect(503); // stub 降级也被计数
      }
      const res = await request(server)
        .post('/v1/foods/estimate')
        .set(auth(token))
        .send({ name: '测试菜10' })
        .expect(429);
      expect(res.body.error.code).toBe('RATE_LIMITED');
    });
  });

  describe('GET /v1/foods/barcode/:code', () => {
    it('非法条码（非 8–14 位数字）→ 400 VALIDATION_ERROR；未认证 → 401', async () => {
      const token = await login(nextPhone());
      const res = await request(server).get('/v1/foods/barcode/123').set(auth(token)).expect(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
      await request(server).get('/v1/foods/barcode/7622210449283').expect(401);
    });
  });
});

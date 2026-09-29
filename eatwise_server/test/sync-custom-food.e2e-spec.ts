import { randomUUID } from 'crypto';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：自定义食物完整下行通道（2026-09-29 拍板）：POST /foods/custom 上行 →
 * /sync/pull customFoodChanges 全量视图（换机拉回自建食物）→ DELETE 软删 →
 * 增量下行 tombstone（客户端据以移除）。STORE_DRIVER=memory 默认。 */
describe('CustomFood sync downlink (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    await request(server)
      .post('/v1/auth/sms/send')
      .send({ phone: '+8613922000066', scene: 'login' })
      .expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({
        phone: '+8613922000066',
        code: '123456',
        device: { deviceId: 'e2e-custom-food-sync', platform: 'android' },
      })
      .expect(200);
    token = res.body.data.accessToken as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = () => ({ Authorization: `Bearer ${token}` });

  it('创建 → pull customFoodChanges 全量视图；删除 → 增量 pull tombstone', async () => {
    // A 机创建自定义食物。
    const created = await request(server)
      .post('/v1/foods/custom')
      .set(auth())
      .send({
        clientRequestId: randomUUID(),
        nameZh: '自制酸奶',
        nameEn: 'Homemade Yogurt',
        aliasesZh: ['酸奶'],
        per100g: { kcal: 60, proteinG: 3.5, carbG: 7, fatG: 2.5 },
        source: 'manual',
      })
      .expect(200);
    const foodId = created.body.data.id as string;

    // B 机首次同步（无 syncToken）→ 全量下行含该自定义食物（含营养字段）。
    const pull1 = await request(server).get('/v1/sync/pull').set(auth()).expect(200);
    const changes = pull1.body.data.customFoodChanges as Array<Record<string, unknown>>;
    expect(changes.length).toBe(1);
    expect(changes[0].entity).toBe('customFood');
    expect(changes[0].id).toBe(foodId);
    expect(changes[0].nameZh).toBe('自制酸奶');
    expect(changes[0].nameEn).toBe('Homemade Yogurt');
    expect(changes[0].aliases).toEqual(['酸奶']);
    expect(changes[0].kcalPer100g).toBe(60);
    expect(changes[0].proteinPer100g).toBe(3.5);
    expect(changes[0].carbsPer100g).toBe(7);
    expect(changes[0].fatPer100g).toBe(2.5);
    expect(changes[0].updatedAt).toBeTruthy();

    // A 机删除（软删 tombstone）。
    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    await request(server).delete(`/v1/foods/custom/${foodId}`).set(auth()).expect(200);

    // B 机增量下行 → tombstone（客户端据以移除本地行）。
    const pull2 = await request(server)
      .get('/v1/sync/pull')
      .query({ syncToken: pull1.body.data.syncToken as string })
      .set(auth())
      .expect(200);
    const changes2 = pull2.body.data.customFoodChanges as Array<{
      tombstone?: { entity: string; id: string; deletedAt: string };
    }>;
    expect(changes2.length).toBe(1);
    expect(changes2[0].tombstone?.entity).toBe('customFood');
    expect(changes2[0].tombstone?.id).toBe(foodId);
    expect(changes2[0].tombstone?.deletedAt).toBeTruthy();
  });
});

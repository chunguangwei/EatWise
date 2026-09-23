import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DataStore } from '../src/common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../src/common/store/store-driver';

const ADMIN = 'test-admin-token';

/**
 * 移动端管理员删除食品（DELETE /v1/moderation/foods/:id，用户 JWT +
 * User.role=admin）e2e：匿名 401 / 普通用户 403；admin 删除任意来源食物 =
 * 与管理台 adminDeleteFood 同口径（软删 + 跨用户级联 tombstone +
 * pending 候选 409 / 缺行 404）。
 */
describe('Mobile admin food delete (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let store: DataStore;
  let driver: StoreDriver;

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
    store = app.get(DataStore);
    driver = app.get(STORE_DRIVER);
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
  });

  let seq = 0;
  function nextPhone(): string {
    seq += 1;
    return `+8613944${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<{ token: string; userId: string }> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-mfoods', platform: 'android' } })
      .expect(200);
    const token = res.body.data.accessToken as string;
    const me = await request(server)
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    return { token, userId: me.body.data.user.id as string };
  }

  async function makeAdmin(userId: string): Promise<void> {
    await request(server)
      .patch(`/v1/admin/users/${userId}/role`)
      .set('x-admin-token', ADMIN)
      .send({ role: 'admin' })
      .expect(200);
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  /** 落一个共享食物 + 指定用户的一条引用记录（跨用户级联断言用）。 */
  async function seedSharedFoodWithEntry(userId: string, foodId: string): Promise<void> {
    store.foods.set(foodId, {
      id: foodId,
      nameZh: '走查重复牛肉干',
      nameEn: 'Dup Beef Jerky',
      aliases: [],
      kcalPer100g: 550,
      proteinPer100g: 45,
      carbsPer100g: 2,
      fatPer100g: 40,
      category: '零食',
      source: 'usda',
    });
    await driver.saveFoodEntry({
      id: `fe_${foodId}`,
      userId,
      clientRequestId: `cr_${foodId}`,
      eatenAt: new Date('2026-09-23T01:00:00.000Z'),
      foodId,
      grams: 100,
      inputMethod: 'manual',
      photoUrl: null,
      nutritionSnapshot: { kcal: 550, proteinG: 45, carbsG: 2, fatG: 40 },
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    });
  }

  it('匿名 → 401；普通用户 → 403', async () => {
    await request(server).delete('/v1/moderation/foods/f_x').expect(401);

    const user = await login(nextPhone());
    await request(server).delete('/v1/moderation/foods/f_x').set(auth(user.token)).expect(403);
  });

  it('admin 删除共享食物：软删 + 跨用户级联 tombstone + 返回 deletedEntries；重删 404', async () => {
    const admin = await login(nextPhone());
    await makeAdmin(admin.userId);
    const other = await login(nextPhone());
    const foodId = 'f_admin_del_shared';
    await seedSharedFoodWithEntry(other.userId, foodId);

    const res = await request(server)
      .delete(`/v1/moderation/foods/${foodId}`)
      .set(auth(admin.token))
      .expect(200);
    expect(res.body.data.deleted).toBe(true);
    expect(res.body.data.deletedEntries).toBe(1);
    // 内存驱动：食物行已移除（prisma 为 tombstone），记录为 tombstone。
    expect(store.foods.get(foodId)).toBeUndefined();
    expect(store.foodEntries.get(`fe_${foodId}`)!.deletedAt).not.toBeNull();

    // 重删 → 404（与管理台同口径）。
    await request(server)
      .delete(`/v1/moderation/foods/${foodId}`)
      .set(auth(admin.token))
      .expect(404);

    // 缺行 → 404。
    await request(server)
      .delete('/v1/moderation/foods/f_ghost_none')
      .set(auth(admin.token))
      .expect(404);
  });

  it('admin 删除：pending 审核候选关联 → 409 FOOD_UNDER_REVIEW，食物未删', async () => {
    const admin = await login(nextPhone());
    await makeAdmin(admin.userId);
    const foodId = 'f_admin_del_pending';
    await seedSharedFoodWithEntry(admin.userId, foodId);
    // pending 候选关联该食物（纠错孪生场景）。
    const now = new Date();
    await driver.createFoodCandidate({
      id: 'fc_admin_del_pending_1',
      foodId,
      userId: admin.userId,
      status: 'pending',
      reason: null,
      kind: 'correction',
      barcode: null,
      evidenceImageUrl: null,
      suggestion: null,
      reviewedBy: null,
      clientRequestId: 'cr_cand_pending_1',
      version: 1,
      createdAt: now,
      updatedAt: now,
    });

    const res = await request(server)
      .delete(`/v1/moderation/foods/${foodId}`)
      .set(auth(admin.token))
      .expect(409);
    expect(res.body.error.code).toBe('FOOD_UNDER_REVIEW');
    expect(store.foods.get(foodId)).toBeDefined();
  });
});

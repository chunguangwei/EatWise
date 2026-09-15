import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { err } from '../src/common/errors/business.exception';
import { BarcodeFoodView, BarcodeService } from '../src/food/barcode/barcode.service';

const ADMIN = 'test-admin-token';

/**
 * e2e：条码查询两级链路——先查自有共享库（条码众包上架商品，source=eatwise，
 * 不再外呼 OFF），未命中回落 OFF 代理（source=openfoodfacts），OFF 也未命中 404 不变。
 * OFF 路径通过 jest.spyOn(BarcodeService, 'lookup') 断言「是否被调用」并隔离外网。
 */
describe('Barcode lookup: own library first, OFF fallback (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let barcodeService: BarcodeService;

  beforeAll(async () => {
    process.env.ADMIN_TOKEN = ADMIN;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
    barcodeService = moduleRef.get(BarcodeService);
  });

  afterAll(async () => {
    await app.close();
    delete process.env.ADMIN_TOKEN;
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  let seq = 0;
  function nextPhone(): string {
    seq += 1;
    return `+8613933${String(seq).padStart(6, '0')}`;
  }

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-barcode', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  let uuidSeq = 0;
  function nextUuid(): string {
    uuidSeq += 1;
    return `c3d4e5f6-${String(uuidSeq).padStart(4, '0')}-4111-8111-111111111111`;
  }

  /** 走完 自定义 → 条码贡献 链路，返回 {foodId, candidateId}；approved=false 时停在 pending */
  async function contributeBarcode(
    token: string,
    nameZh: string,
    barcode: string,
  ): Promise<{ foodId: string; candidateId: string }> {
    const created = await request(server)
      .post('/v1/foods/custom')
      .set(auth(token))
      .send({
        clientRequestId: nextUuid(),
        nameZh,
        per100g: { kcal: 480, proteinG: 4.7, carbG: 68.5, fatG: 20.4 },
        source: 'manual',
      })
      .expect(200);
    const contributed = await request(server)
      .post(`/v1/foods/custom/${created.body.data.id}/contribute`)
      .set(auth(token))
      .send({ clientRequestId: nextUuid(), barcode, evidenceImageUrl: '/v1/uploads/n.jpg' })
      .expect(200);
    return {
      foodId: created.body.data.id as string,
      candidateId: contributed.body.data.id as string,
    };
  }

  const OFF_VIEW: BarcodeFoodView = {
    id: 'off_7622210449999',
    barcode: '7622210449999',
    nameZh: 'OFF 夹心饼干',
    nameEn: 'OFF Sandwich Biscuit',
    aliases: [],
    kcalPer100g: 480,
    proteinPer100g: 4.7,
    carbsPer100g: 68.5,
    fatPer100g: 20.4,
    source: 'openfoodfacts',
    isCustom: false,
  };

  it('自有库命中（众包上架后）：source=eatwise，OFF 代理不被调用', async () => {
    const token = await login(nextPhone());
    const barcode = '6901234567892';
    const { foodId, candidateId } = await contributeBarcode(token, '闭环威化', barcode);
    await request(server)
      .post(`/v1/admin/food-candidates/${candidateId}/review`)
      .set('x-admin-token', ADMIN)
      .send({ action: 'approve' })
      .expect(200);

    const spy = jest.spyOn(barcodeService, 'lookup');
    const res = await request(server)
      .get(`/v1/foods/barcode/${barcode}`)
      .set(auth(token))
      .expect(200);
    expect(res.body.data).toEqual({
      id: foodId,
      barcode,
      nameZh: '闭环威化',
      nameEn: '闭环威化',
      aliases: [],
      kcalPer100g: 480,
      proteinPer100g: 4.7,
      carbsPer100g: 68.5,
      fatPer100g: 20.4,
      source: 'eatwise',
      isCustom: false,
    });
    expect(spy).not.toHaveBeenCalled(); // 自有库命中不打 OFF
  });

  it('pending（未上架）不命中自有库：回落 OFF 代理', async () => {
    const token = await login(nextPhone());
    const barcode = '6901234567893';
    await contributeBarcode(token, '未上架威化', barcode);

    const spy = jest.spyOn(barcodeService, 'lookup').mockRejectedValue(err.barcodeNotFound());
    await request(server).get(`/v1/foods/barcode/${barcode}`).set(auth(token)).expect(404);
    expect(spy).toHaveBeenCalledWith(barcode);
  });

  it('自有库未命中 → 回落 OFF 命中：source=openfoodfacts', async () => {
    const token = await login(nextPhone());
    const spy = jest.spyOn(barcodeService, 'lookup').mockResolvedValue(OFF_VIEW);
    const res = await request(server)
      .get('/v1/foods/barcode/7622210449999')
      .set(auth(token))
      .expect(200);
    expect(res.body.data.source).toBe('openfoodfacts');
    expect(res.body.data.barcode).toBe('7622210449999');
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('自有库与 OFF 均未命中 → 404 FOOD_BARCODE_NOT_FOUND（与现状一致）', async () => {
    const token = await login(nextPhone());
    jest.spyOn(barcodeService, 'lookup').mockRejectedValue(err.barcodeNotFound());
    const res = await request(server)
      .get('/v1/foods/barcode/6999999999999')
      .set(auth(token))
      .expect(404);
    expect(res.body.error.code).toBe('FOOD_BARCODE_NOT_FOUND');
  });

  it('条码格式非法 → 400 VALIDATION_ERROR（格式校验仍在 OFF 路径统一报）', async () => {
    const token = await login(nextPhone());
    const spy = jest.spyOn(barcodeService, 'lookup');
    const res = await request(server).get('/v1/foods/barcode/123').set(auth(token)).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(spy).toHaveBeenCalledWith('123'); // 自有库直接跳过，交给 OFF 路径报格式错
  });

  it('未认证 → 401（端点鉴权不变）', async () => {
    await request(server).get('/v1/foods/barcode/6901234567892').expect(401);
  });
});

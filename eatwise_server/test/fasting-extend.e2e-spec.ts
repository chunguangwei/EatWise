import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：F3 延长后 F1 状态不丢记录/不重复建档；X-Timezone 非法值回退不 500 */
describe('Fasting extend & timezone (e2e)', () => {
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

  async function login(phone: string): Promise<string> {
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-fasting', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  /** 选一个当前时刻本地约为 08:xx 的 IANA 时区 → 默认 16:8（12:00–20:00）必处于断食窗口 */
  function fastingTz(): string {
    let offset = (8 - new Date().getUTCHours() + 24) % 24;
    if (offset > 14) offset -= 24;
    if (offset === 0) return 'Etc/UTC';
    return offset > 0 ? `Etc/GMT-${offset}` : `Etc/GMT+${-offset}`;
  }

  it('延长后再次查询状态：activeRecord 同一记录、extendedMinutes 累计、不重复建档', async () => {
    const token = await login('+8613911000001');
    const tz = fastingTz();
    const auth = (r: request.Test) =>
      r.set('Authorization', `Bearer ${token}`).set('X-Timezone', tz);

    const s1 = await auth(request(server).get('/v1/fasting/status')).expect(200);
    expect(s1.body.data.state).toBe('fasting');
    const record = s1.body.data.activeRecord;
    expect(record).toBeTruthy();

    const ext = await request(server)
      .post('/v1/fasting/extend')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientRequestId: randomUUID(), recordId: record.id, extendMinutes: 30 })
      .expect(200);
    expect(ext.body.data.extendedMinutes).toBe(30);
    expect(ext.body.data.extendRemainingMinutes).toBe(210);

    // 修复前：plannedEndAt 后移后按窗口精确匹配找不到旧记录 → 重复建档 / 状态丢失
    const s2 = await auth(request(server).get('/v1/fasting/status')).expect(200);
    expect(s2.body.data.state).toBe('fasting');
    expect(s2.body.data.activeRecord.id).toBe(record.id);
    expect(s2.body.data.activeRecord.extendedMinutes).toBe(30);
  });

  it('非法 X-Timezone → 回退 profile 时区，200 不 500', async () => {
    const token = await login('+8613911000002');
    const res = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Not/AZone')
      .expect(200);
    expect(['fasting', 'eating']).toContain(res.body.data.state);
  });

  it('合法 X-Timezone 仍然生效（断食窗口判定按 header 时区）', async () => {
    const token = await login('+8613911000003');
    const res = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', fastingTz())
      .expect(200);
    expect(res.body.data.state).toBe('fasting');
  });
});

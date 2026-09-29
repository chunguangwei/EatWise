import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：/fasting/end 归属防御——endedAt 落在记录窗口外 → 409 FASTING_END_OUT_OF_WINDOW，记录不被结掉 */
describe('Fasting end out-of-window guard (e2e)', () => {
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
      .send({ phone, code: '123456', device: { deviceId: 'e2e-end', platform: 'ios' } })
      .expect(200);
    return res.body.data.accessToken as string;
  }

  /** 上海时区当前时刻（分钟，mod 1440） */
  function shanghaiMinutesNow(): number {
    const d = new Date(Date.now() + 8 * 3600_000);
    return d.getUTCHours() * 60 + d.getUTCMinutes();
  }

  const fmt = (mins: number) => {
    const m = ((mins % 1440) + 1440) % 1440;
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  };

  it('endedAt 早于窗口开始 → 409 FASTING_END_OUT_OF_WINDOW，activeRecord 仍 on_track', async () => {
    const token = await login('+8613911000110');
    // 动态方案：进食窗口 = [现在+1h, 现在+9h]（16:8），保证「现在」必在断食窗口内，
    // 与用例运行的真实时刻无关。当前周期：plannedStart=现在−15h，plannedEnd=现在+1h。
    const nowMin = shanghaiMinutesNow();
    await request(server)
      .put('/v1/fasting-plans/current')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .send({
        clientRequestId: randomUUID(),
        planType: '16:8',
        eatingWindow: { start: fmt(nowMin + 60), end: fmt(nowMin + 540) },
      })
      .expect(200);

    // 物化当前周期记录（find-or-create）
    const status = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    const active = status.body.data.activeRecord as { id: string; result: string } | null;
    expect(active).not.toBeNull();
    expect(active!.result).toBe('on_track');

    // 归属错误上报：endedAt = 现在−16h < plannedStart（现在−15h）−15min 容差
    const endedAt = new Date(Date.now() - 16 * 3600_000).toISOString();
    const res = await request(server)
      .post('/v1/fasting/end')
      .set('Authorization', `Bearer ${token}`)
      .send({ clientRequestId: randomUUID(), recordId: active!.id, endedAt })
      .expect(409);
    expect(res.body.error.code).toBe('FASTING_END_OUT_OF_WINDOW');

    // 当前记录未被结掉
    const after = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    expect(after.body.data.activeRecord?.id).toBe(active!.id);
    expect(after.body.data.activeRecord?.result).toBe('on_track');
  });

  it('F4 断食历史：区间返回已物化记录；非法区间 400 VALIDATION_ERROR', async () => {
    const token = await login('+8613911000111');
    const nowMin = shanghaiMinutesNow();
    await request(server)
      .put('/v1/fasting-plans/current')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .send({
        clientRequestId: randomUUID(),
        planType: '16:8',
        eatingWindow: { start: fmt(nowMin + 60), end: fmt(nowMin + 540) },
      })
      .expect(200);
    const status = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    const active = status.body.data.activeRecord as { id: string } | null;
    expect(active).not.toBeNull();

    // 上海时区自然日（to 放到明天，覆盖跨午夜归属）。
    const day = (offsetDays: number) =>
      new Date(Date.now() + 8 * 3600_000 + offsetDays * 86400_000).toISOString().slice(0, 10);
    const res = await request(server)
      .get(`/v1/fasting/records?from=${day(-13)}&to=${day(1)}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data.length).toBeGreaterThanOrEqual(1);
    expect(res.body.data[0].id).toBe(active!.id);

    const bad = await request(server)
      .get(`/v1/fasting/records?from=${day(0)}&to=${day(-1)}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(400);
    expect(bad.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('B2 窗口签名：不一致 409 FASTING_WINDOW_MISMATCH 且记录不动；一致正常结算', async () => {
    const token = await login('+8613911000112');
    const nowMin = shanghaiMinutesNow();
    await request(server)
      .put('/v1/fasting-plans/current')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .send({
        clientRequestId: randomUUID(),
        planType: '16:8',
        eatingWindow: { start: fmt(nowMin + 60), end: fmt(nowMin + 540) },
      })
      .expect(200);
    const status = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    const active = status.body.data.activeRecord as {
      id: string;
      plannedStartAt: string;
      plannedEndAt: string;
      result: string;
    } | null;
    expect(active).not.toBeNull();

    // 分叉端签名（偏 3h）→ 409，记录保持 on_track
    const skewStart = new Date(Date.parse(active!.plannedStartAt) - 3 * 3600_000).toISOString();
    const skewEnd = new Date(Date.parse(active!.plannedEndAt) - 3 * 3600_000).toISOString();
    const res = await request(server)
      .post('/v1/fasting/end')
      .set('Authorization', `Bearer ${token}`)
      .send({
        clientRequestId: randomUUID(),
        recordId: active!.id,
        endedAt: new Date().toISOString(),
        plannedStartAt: skewStart,
        plannedEndAt: skewEnd,
      })
      .expect(409);
    expect(res.body.error.code).toBe('FASTING_WINDOW_MISMATCH');

    const after = await request(server)
      .get('/v1/fasting/status')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timezone', 'Asia/Shanghai')
      .expect(200);
    expect(after.body.data.activeRecord?.result).toBe('on_track');

    // 签名一致（取服务端记录窗口锚点）→ 正常结算 completed
    await request(server)
      .post('/v1/fasting/end')
      .set('Authorization', `Bearer ${token}`)
      .send({
        clientRequestId: randomUUID(),
        recordId: active!.id,
        endedAt: active!.plannedEndAt,
        plannedStartAt: active!.plannedStartAt,
        plannedEndAt: active!.plannedEndAt,
      })
      .expect(200);
    const day = (offsetDays: number) =>
      new Date(Date.now() + 8 * 3600_000 + offsetDays * 86400_000).toISOString().slice(0, 10);
    const settled = await request(server)
      .get(`/v1/fasting/records?from=${day(-13)}&to=${day(1)}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    const rec = ((settled.body.data ?? []) as Array<{ id: string; result: string }>).find(
      (r) => r.id === active!.id,
    );
    expect(rec?.result).toBe('completed');
  });
});

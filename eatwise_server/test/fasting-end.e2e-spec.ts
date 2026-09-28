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
});

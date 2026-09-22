import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/**
 * 全局限流守卫回归（走查 SEC-RATE-THROTLER-DEAD）：ThrottlerModule 注册 ≠
 * 生效——守卫必须经 APP_GUARD 绑定才有 429 行为；THROTTLE_LIMIT env 可调
 * （e2e setup 默认放大，本 spec 用小限额触发）。
 */
describe('全局 ThrottlerGuard 绑定（契约 §6.1）', () => {
  let app: INestApplication;

  beforeAll(async () => {
    process.env.THROTTLE_LIMIT = '3';
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    delete process.env.THROTTLE_LIMIT;
    await app?.close();
  });

  it('限额内 200、超限 429 TOO_MANY_REQUESTS', async () => {
    for (let i = 0; i < 3; i++) {
      await request(app.getHttpServer()).get('/health').expect(200);
    }
    await request(app.getHttpServer()).get('/health').expect(429);
  });
});

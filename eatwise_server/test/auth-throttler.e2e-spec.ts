import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('密码登录独立限流 (e2e)', () => {
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

  it('同一 IP 每分钟前 5 次进入认证，第 6 次 429；短信登录不受影响', async () => {
    for (let i = 0; i < 5; i++) {
      const res = await request(server)
        .post('/v1/auth/login')
        .send({ username: 'rate_limit_ghost', password: 'Passw0rd123' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_INVALID_CREDENTIALS');
    }
    await request(server)
      .post('/v1/auth/login')
      .send({ username: 'rate_limit_ghost', password: 'Passw0rd123' })
      .expect(429);

    const phone = '+8613900000101';
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    await request(server).post('/v1/auth/login/phone').send({ phone, code: '123456' }).expect(200);
  });
});

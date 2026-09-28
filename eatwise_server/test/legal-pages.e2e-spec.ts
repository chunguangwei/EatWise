import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：法务静态页 /privacy、/terms（匿名可访问，App Store 要求公网 URL；不带 /v1 前缀） */
describe('Legal pages (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', {
      exclude: [
        { path: 'admin', method: RequestMethod.GET },
        { path: 'privacy', method: RequestMethod.GET },
        { path: 'terms', method: RequestMethod.GET },
      ],
    });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /privacy → 匿名 200 HTML，中英双文 + 生效日期 + 联系方式 + 存储地', async () => {
    const res = await request(server).get('/privacy').expect(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.text).toContain('隐私政策');
    expect(res.text).toContain('Privacy Policy');
    expect(res.text).toContain('2026-09-28'); // 生效日期
    expect(res.text).toContain('chunguangwee@gmail.com');
    expect(res.text).toContain('美国');
    expect(res.text).toContain('United States');
  });

  it('GET /terms → 匿名 200 HTML，中英双文 + 联系方式；/v1 前缀下不可达', async () => {
    const res = await request(server).get('/terms').expect(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.text).toContain('用户协议');
    expect(res.text).toContain('Terms of Use');
    expect(res.text).toContain('chunguangwee@gmail.com');
    await request(server).get('/v1/terms').expect(404);
  });
});

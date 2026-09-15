import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：/admin 管理控制台静态页（内嵌单文件 HTML，不带 /v1 前缀） */
describe('Admin console static page (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /admin → 200 HTML，包含关键元素；不带 /v1 前缀', async () => {
    const res = await request(server).get('/admin').expect(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.text).toContain('管理控制台');
    expect(res.text).toContain('x-admin-token');
    expect(res.text).toContain('/admin/food-candidates');
    expect(res.text).toContain('/admin/posts');
  });
});

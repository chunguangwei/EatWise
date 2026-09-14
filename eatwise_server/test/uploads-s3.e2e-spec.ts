import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

// s3 驱动环境：必须在导入 AppModule 之前设置（工厂在模块编译时读 env）。
// 凭据为假值——本文件只走 GET 重定向路径，S3Client 构造与 resolve 均不发网络请求。
process.env.STORAGE_DRIVER = 's3';
process.env.S3_BUCKET = 'eatwise-e2e-bucket';
process.env.S3_ACCESS_KEY = 'e2e-fake-ak';
process.env.S3_SECRET = 'e2e-fake-sk';
process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';
process.env.CDN_BASE_URL = 'https://cdn.e2e.example.com';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { AppModule } = require('../src/app.module') as typeof import('../src/app.module');

/** e2e：STORAGE_DRIVER=s3 时 GET /v1/uploads/:filename 302 到 CDN（公开读契约不变） */
describe('Uploads s3 驱动 (e2e)', () => {
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

  it('s3 模式必需 env 齐备 → 应用正常启动（beforeAll 即验证）', () => {
    expect(app).toBeDefined();
  });

  it('U2 合法文件名 → 302，Location 指向 CDN_BASE_URL/<filename>', async () => {
    const id = 'a1b2c3d4-0000-4000-8000-0000000000ab.png';
    const res = await request(server).get(`/v1/uploads/${id}`).expect(302);
    expect(res.headers.location).toBe(`https://cdn.e2e.example.com/${id}`);
  });

  it('U2 白名单外文件名（路径穿越/非法形态）仍一律 404，不重定向', async () => {
    for (const evil of ['..', '..%2f.env', 'package.json', 'a..png', 'not-an-image.gif']) {
      const res = await request(server).get(`/v1/uploads/${evil}`);
      expect([res.status, evil]).toEqual([404, evil]);
    }
  });

  it('STORAGE_DRIVER=s3 缺必需 env → 模块编译即 fail fast（报缺失变量名）', async () => {
    const bucket = process.env.S3_BUCKET;
    delete process.env.S3_BUCKET;
    try {
      await expect(Test.createTestingModule({ imports: [AppModule] }).compile()).rejects.toThrow(
        /S3_BUCKET/,
      );
    } finally {
      process.env.S3_BUCKET = bucket;
    }
  });
});

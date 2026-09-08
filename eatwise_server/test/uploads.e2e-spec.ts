import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import request from 'supertest';

// 上传目录指向临时目录：必须在导入 AppModule（求值 UPLOAD_ROOT）之前设置。
process.env.UPLOAD_DIR = mkdtempSync(join(tmpdir(), 'eatwise-uploads-'));

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { AppModule } = require('../src/app.module') as typeof import('../src/app.module');

// 最小合法图片（各格式文件头 + 填充字节；服务端按魔数校验声明的 mimetype）。
const PNG = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c6300010000050001',
  'hex',
);
const JPEG = Buffer.concat([
  Buffer.from('ffd8ffe000104a464900010100000100010000ff', 'hex'),
  Buffer.alloc(64, 0x20),
  Buffer.from('ffd9', 'hex'),
]);
const WEBP = Buffer.concat([
  Buffer.from('RIFF', 'ascii'),
  Buffer.alloc(4, 0),
  Buffer.from('WEBPVP8 ', 'ascii'),
  Buffer.alloc(32, 0x01),
]);
const GIF = Buffer.from(
  '4749463839610100010080000000000021f90401000000002c000000000100010000020042',
  'hex',
);

/** e2e：图片上传 U1/U2（类型白名单 + 魔数一致性 / 5MB 上限 / 静态读取 / 路径穿越） */
describe('Uploads (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    const phone = '+8613966000001';
    await request(server).post('/v1/auth/sms/send').send({ phone, scene: 'login' }).expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({ phone, code: '123456', device: { deviceId: 'e2e-uploads', platform: 'ios' } })
      .expect(200);
    token = res.body.data.accessToken as string;
  });

  afterAll(async () => {
    await app.close();
    rmSync(process.env.UPLOAD_DIR as string, { recursive: true, force: true });
  });

  const post = (buf: Buffer, type: string, name = 'photo') =>
    request(server)
      .post('/v1/uploads')
      .set('Authorization', `Bearer ${token}`)
      .field('filename', name)
      .attach('file', buf, {
        filename: `${name}.${type === 'image/jpeg' ? 'jpg' : type.split('/')[1]}`,
        contentType: type,
      });

  it('U1 上传 png → 201 {id, url}，id 为 uuid.jpg/png/webp 形态；url 即 GET 路径', async () => {
    const res = await post(PNG, 'image/png').expect(201);
    const { id, url } = res.body.data as { id: string; url: string };
    expect(id).toMatch(/^[a-f0-9-]{36}\.png$/);
    expect(url).toBe(`/v1/uploads/${id}`);
  });

  it('U1 jpg / webp 同样放行（扩展名取自声明类型，非客户端文件名）', async () => {
    const jpg = await post(JPEG, 'image/jpeg', 'evil.jpeg.txt').expect(201);
    expect(jpg.body.data.id).toMatch(/\.jpg$/);
    const webp = await post(WEBP, 'image/webp').expect(201);
    expect(webp.body.data.id).toMatch(/\.webp$/);
  });

  it('U1 非法类型 415 UPLOAD_TYPE_UNSUPPORTED（gif 声明 gif 也被白名单挡下）', async () => {
    const res = await post(GIF, 'image/gif').expect(415);
    expect(res.body.error.code).toBe('UPLOAD_TYPE_UNSUPPORTED');
  });

  it('U1 声明 png 但字节是 gif → 魔数不一致按非法类型拒绝（不落盘）', async () => {
    const res = await post(GIF, 'image/png').expect(415);
    expect(res.body.error.code).toBe('UPLOAD_TYPE_UNSUPPORTED');
  });

  it('U1 超 5MB → 413 UPLOAD_FILE_TOO_LARGE', async () => {
    const big = Buffer.concat([PNG, Buffer.alloc(5 * 1024 * 1024 + 1, 0x41)]);
    const res = await post(big, 'image/png').expect(413);
    expect(res.body.error.code).toBe('UPLOAD_FILE_TOO_LARGE');
  });

  it('U1 缺 file 字段 → 400 VALIDATION_ERROR', async () => {
    const res = await request(server)
      .post('/v1/uploads')
      .set('Authorization', `Bearer ${token}`)
      .field('note', 'no file part')
      .expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('U1 未登录 → 401', async () => {
    await request(server).post('/v1/uploads').attach('file', PNG, 'a.png').expect(401);
  });

  it('U2 读取（无 Authorization 头）：Content-Type 按扩展名，字节与上传一致', async () => {
    const { id } = (await post(PNG, 'image/png').expect(201)).body.data as { id: string };
    const res = await request(server).get(`/v1/uploads/${id}`).expect(200);
    expect(res.headers['content-type']).toBe('image/png');
    expect(res.headers['cache-control']).toContain('immutable');
    expect(Buffer.compare(res.body, PNG)).toBe(0);

    const jpg = (await post(JPEG, 'image/jpeg').expect(201)).body.data as { id: string };
    const res2 = await request(server).get(`/v1/uploads/${jpg.id}`).expect(200);
    expect(res2.headers['content-type']).toBe('image/jpeg');
  });

  it('U2 未知文件名 → 404；路径穿越一律 404（含编码斜杠）', async () => {
    await request(server).get('/v1/uploads/00000000-0000-4000-8000-000000000000.png').expect(404);
    for (const evil of [
      '..',
      '..%2f..%2fpackage.json',
      '..%2f%2e%2e%2fpackage.json',
      'package.json',
      '..%2f.env',
      'a..png',
      '%2e%2e%2f%2e%2e%2f.env',
    ]) {
      const res = await request(server).get(`/v1/uploads/${evil}`);
      expect([res.status, evil]).toEqual([404, evil]);
    }
  });
});

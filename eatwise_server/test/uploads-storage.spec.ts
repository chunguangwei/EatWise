import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { ConfigService } from '@nestjs/config';
import { mkdtempSync, readFileSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

// 上传目录指向临时目录：必须在导入被测模块（求值 UPLOAD_ROOT）之前设置。
const UPLOAD_DIR = mkdtempSync(join(tmpdir(), 'eatwise-storage-spec-'));
process.env.UPLOAD_DIR = UPLOAD_DIR;

/* eslint-disable @typescript-eslint/no-var-requires */
const { LocalUploadsStorage } =
  require('../src/uploads/local-uploads.storage') as typeof import('../src/uploads/local-uploads.storage');
const { S3UploadsStorage } =
  require('../src/uploads/s3-uploads.storage') as typeof import('../src/uploads/s3-uploads.storage');
/* eslint-enable @typescript-eslint/no-var-requires */

// 最小合法 PNG（文件头魔数 + 填充字节）。
const PNG = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c6300010000050001',
  'hex',
);

/** 存储驱动单测：local 落盘/读取定位、s3 PUT 入参与 url 拼接、env fail fast */
describe('UploadsStorage 驱动', () => {
  afterAll(() => {
    rmSync(UPLOAD_DIR, { recursive: true, force: true });
  });

  describe('LocalUploadsStorage（STORAGE_DRIVER=local，默认）', () => {
    it('save 落盘到 UPLOAD_ROOT，返回 {id, url=/v1/uploads/<id>}，字节一致', async () => {
      const storage = new LocalUploadsStorage();
      await storage.onModuleInit();

      const id = 'a1b2c3d4-0000-4000-8000-000000000001.png';
      const result = await storage.save(id, PNG);

      expect(result).toEqual({ id, url: `/v1/uploads/${id}` });
      expect(readFileSync(join(UPLOAD_DIR, id)).equals(PNG)).toBe(true);
    });

    it('resolve 已存在文件 → {kind:file, path 落在 uploads/ 内}', async () => {
      const storage = new LocalUploadsStorage();
      await storage.onModuleInit();
      const id = 'a1b2c3d4-0000-4000-8000-000000000002.jpg';
      await storage.save(id, PNG);

      const target = await storage.resolve(id);
      expect(target.kind).toBe('file');
      if (target.kind === 'file') expect(target.path).toBe(join(UPLOAD_DIR, id));
    });

    it('resolve 不存在的文件名 → 404 NOT_FOUND', async () => {
      const storage = new LocalUploadsStorage();
      await expect(
        storage.resolve('a1b2c3d4-0000-4000-8000-999999999999.png'),
      ).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });
  });

  describe('S3UploadsStorage（STORAGE_DRIVER=s3）', () => {
    const config = {
      bucket: 'eatwise-uploads',
      cdnBaseUrl: 'https://cdn.example.com',
      region: 'auto',
      accessKey: 'ak',
      secret: 'sk',
      endpoint: 'https://account.r2.cloudflarestorage.com',
    };

    const makeClient = () => {
      const send = jest.fn().mockResolvedValue({});
      return { send, client: { send } as unknown as S3Client };
    };

    it('save 发 PutObject（Bucket/Key/Body/ContentType/一年强缓存），url 拼 CDN 域名', async () => {
      const { send, client } = makeClient();
      const storage = new S3UploadsStorage(config, client);

      const id = 'a1b2c3d4-0000-4000-8000-000000000003.webp';
      const result = await storage.save(id, PNG, 'image/webp');

      expect(send).toHaveBeenCalledTimes(1);
      const command = send.mock.calls[0][0] as PutObjectCommand;
      expect(command).toBeInstanceOf(PutObjectCommand);
      expect(command.input).toMatchObject({
        Bucket: 'eatwise-uploads',
        Key: id,
        ContentType: 'image/webp',
        CacheControl: 'public, max-age=31536000, immutable',
      });
      expect((command.input.Body as Buffer).equals(PNG)).toBe(true);
      expect(result).toEqual({ id, url: `https://cdn.example.com/${id}` });
    });

    it('resolve 直接给 CDN 重定向地址（不查存在性、不发请求）', async () => {
      const { send, client } = makeClient();
      const storage = new S3UploadsStorage(config, client);

      const id = 'a1b2c3d4-0000-4000-8000-000000000004.png';
      await expect(storage.resolve(id)).resolves.toEqual({
        kind: 'redirect',
        url: `https://cdn.example.com/${id}`,
      });
      expect(send).not.toHaveBeenCalled();
    });

    it('fromEnv 必需项缺失 → 启动即 fail fast（报出缺失变量名）', () => {
      expect(() => S3UploadsStorage.fromEnv(new ConfigService({ S3_BUCKET: 'b' }))).toThrow(
        /S3_ACCESS_KEY、S3_SECRET、CDN_BASE_URL/,
      );
    });

    it('fromEnv 齐备 → 构建成功；S3_REGION 缺省 auto、CDN_BASE_URL 尾斜杠归一', async () => {
      const storage = S3UploadsStorage.fromEnv(
        new ConfigService({
          S3_BUCKET: 'b',
          S3_ACCESS_KEY: 'ak',
          S3_SECRET: 'sk',
          CDN_BASE_URL: 'https://cdn.example.com/',
          S3_ENDPOINT: config.endpoint,
        }),
      );
      // 借 resolve 验证 url 拼接（尾斜杠不重复）
      await expect(storage.resolve('x.png')).resolves.toEqual({
        kind: 'redirect',
        url: 'https://cdn.example.com/x.png',
      });
    });
  });
});

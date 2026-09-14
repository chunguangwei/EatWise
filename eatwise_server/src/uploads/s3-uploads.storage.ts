import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { ConfigService } from '@nestjs/config';
import { StoredUpload, UploadReadTarget, UploadsStorage } from './uploads.storage';

/** S3 驱动运行配置（fromEnv 校验后保证必填项齐备）。 */
export interface S3UploadsConfig {
  bucket: string;
  /** 公开读域名（CDN 或桶公开地址），对外 url 一律拼在它后面。 */
  cdnBaseUrl: string;
  region: string;
  accessKey: string;
  secret: string;
  /** R2 等 S3 兼容服务必填；AWS S3 留空走默认端点。 */
  endpoint?: string;
}

/**
 * 对象存储驱动（STORAGE_DRIVER=s3，部署手册 §3 上线形态）：图片 PUT 到
 * R2/S3 桶（Key 即文件名），公开读走 CDN——save 返回 `${CDN_BASE_URL}/${id}`，
 * GET /v1/uploads/:filename 由 controller 302 到同一地址（端点契约不变，
 * 老客户端与 Image.network 公开读无感）。
 * 对象内容不可变（文件名含 uuid），CacheControl 按一年强缓存下发。
 */
export class S3UploadsStorage implements UploadsStorage {
  constructor(
    private readonly config: S3UploadsConfig,
    private readonly client: S3Client,
  ) {}

  /**
   * 从环境变量构建（UploadsModule 工厂调用）：STORAGE_DRIVER=s3 且必需
   * env 缺失时启动即抛错（fail fast），杜绝运行到首次上传才炸。
   */
  static fromEnv(config: ConfigService): S3UploadsStorage {
    const missing = ['S3_BUCKET', 'S3_ACCESS_KEY', 'S3_SECRET', 'CDN_BASE_URL'].filter(
      (key) => !config.get<string>(key),
    );
    if (missing.length > 0) {
      throw new Error(`STORAGE_DRIVER=s3 需要配置环境变量：${missing.join('、')}`);
    }
    const cfg: S3UploadsConfig = {
      bucket: config.getOrThrow<string>('S3_BUCKET'),
      // 去掉尾斜杠，拼 url 时统一由本类补分隔符
      cdnBaseUrl: config.getOrThrow<string>('CDN_BASE_URL').replace(/\/+$/, ''),
      region: config.get<string>('S3_REGION', 'auto'),
      accessKey: config.getOrThrow<string>('S3_ACCESS_KEY'),
      secret: config.getOrThrow<string>('S3_SECRET'),
      endpoint: config.get<string>('S3_ENDPOINT') || undefined,
    };
    const client = new S3Client({
      region: cfg.region,
      endpoint: cfg.endpoint,
      // 自定义端点（R2/MinIO 等 S3 兼容服务）走 path-style；AWS S3 保持默认虚拟主机式
      forcePathStyle: Boolean(cfg.endpoint),
      credentials: { accessKeyId: cfg.accessKey, secretAccessKey: cfg.secret },
    });
    return new S3UploadsStorage(cfg, client);
  }

  /** PUT 到桶（Key=id），返回 CDN 公开读 url。 */
  async save(id: string, buffer: Buffer, contentType: string): Promise<StoredUpload> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.config.bucket,
        Key: id,
        Body: buffer,
        ContentType: contentType,
        CacheControl: 'public, max-age=31536000, immutable',
      }),
    );
    return { id, url: `${this.config.cdnBaseUrl}/${id}` };
  }

  /**
   * 不查存在性直接给 CDN 地址：存在性 HEAD 会让每次读图多一跳回源，
   * 且重定向后对象不存在时 CDN 自身即回 404，语义不丢。
   */
  resolve(filename: string): Promise<UploadReadTarget> {
    return Promise.resolve({
      kind: 'redirect',
      url: `${this.config.cdnBaseUrl}/${filename}`,
    });
  }
}

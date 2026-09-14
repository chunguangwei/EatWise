import { resolve } from 'path';
/** 上传文件存储约定（类型白名单 + 文件名规则 + 驱动抽象），service / controller 共用。 */

/** PNG 文件头（8 字节定长签名，嗅探用）。 */
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** 允许的图片类型 → 落盘扩展名（契约：仅 jpg/png/webp）。 */
export const ALLOWED_IMAGE_TYPES: Readonly<Record<string, string>> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/** 单文件大小上限 5MB（超限 multer 抛 LIMIT_FILE_SIZE → 413）。 */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

/**
 * 落盘文件名白名单：uuid 生成的小写字母/数字/连字符 + 受支持扩展名。
 * GET 侧据此拒绝任何路径穿越/越界文件名（`..`、`%2f`、绝对路径均不匹配）。
 */
export const UPLOAD_FILENAME_PATTERN = /^[a-z0-9-]+\.(?:jpg|png|webp)$/;

/** 存储根目录（server 根下 uploads/，已 gitignore；UPLOAD_DIR 供测试隔离覆盖）。 */
export const UPLOAD_ROOT = resolve(process.env.UPLOAD_DIR ?? 'uploads');

/** multer 在 @UploadedFile() 上挂载的文件元信息（本模块用到的子集）。 */
export interface UploadedImage {
  fieldname: string;
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

/** 落盘/落桶结果：id 即文件名（对象 Key），url 为对外读取地址。 */
export interface StoredUpload {
  id: string;
  url: string;
}

/**
 * GET 读取定位（驱动间形态不同，判别联合交由 controller 分支）：
 * local —— 落盘绝对路径，controller sendFile 直出；
 * s3    —— CDN 公开读 URL，controller 302 重定向（端点契约不变，老客户端无感）。
 */
export type UploadReadTarget = { kind: 'file'; path: string } | { kind: 'redirect'; url: string };

/** DI token：STORAGE_DRIVER 环境变量选择 LocalUploadsStorage / S3UploadsStorage */
export const UPLOADS_STORAGE = 'UPLOADS_STORAGE';

/**
 * 图片存储驱动抽象（对象存储迁移，部署手册 §3）：业务侧（UploadsService）
 * 只做魔数嗅探与文件名白名单校验，读写具体落到哪个介质由本接口的实现决定；
 * 由环境变量 STORAGE_DRIVER=local|s3 选择（默认 local，见 UploadsModule），
 * 组织模式与 STORE_DRIVER（common/store/store-driver.ts）一致。
 * id/文件名由调用方生成（`${uuid}.${ext}`，已过白名单），实现方不再校验合法性。
 */
export interface UploadsStorage {
  /** 写入一张已通过魔数校验的图片，返回 id 与对外 url。 */
  save(id: string, buffer: Buffer, contentType: string): Promise<StoredUpload>;
  /** 文件名的读取定位（local 查存在性，不存在 404；s3 直接给 CDN 地址）。 */
  resolve(filename: string): Promise<UploadReadTarget>;
}

/**
 * 图片真实格式嗅探（文件头魔数）：扩展名与 Content-Type 一律以此为准，
 * 既不信客户端文件名，也不信 multipart 里声明的 mimetype —— 否则一份
 * 任意字节改名 `.png` 就能以 image/png 落盘并被浏览器按图片渲染。
 * 白名单外的格式（gif/bmp/…）返回 undefined，调用方按非法类型拒绝。
 */
export function sniffImageMimetype(buffer: Buffer): string | undefined {
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(PNG_MAGIC)) return 'image/png';
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff)
    return 'image/jpeg';
  if (
    buffer.length >= 12 &&
    buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buffer.subarray(8, 12).toString('ascii') === 'WEBP'
  )
    return 'image/webp';
  return undefined;
}

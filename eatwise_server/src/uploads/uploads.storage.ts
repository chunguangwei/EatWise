import { resolve } from 'path';
/** 上传文件存储约定（类型白名单 + 文件名规则），service / controller 共用。 */

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

import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { newId } from '../common/utils/id.util';
import {
  ALLOWED_IMAGE_TYPES,
  StoredUpload,
  UPLOADS_STORAGE,
  UPLOAD_FILENAME_PATTERN,
  UploadReadTarget,
  UploadedImage,
  UploadsStorage,
  sniffImageMimetype,
} from './uploads.storage';

export { StoredUpload };

/**
 * 图片上传（打卡配图链路）的业务入口：负责与介质无关的部分——文件头魔数
 * 嗅探（不信客户端文件名，也不信 multipart 声明的 mimetype）、uuid 文件名
 * 生成、GET 侧文件名白名单；读写落到哪个介质委派给 UploadsStorage 驱动
 * （STORAGE_DRIVER=local|s3，见 UploadsModule），端点契约与驱动无关。
 */
@Injectable()
export class UploadsService {
  constructor(@Inject(UPLOADS_STORAGE) private readonly storage: UploadsStorage) {}

  /**
   * 存一张图片，返回文件名与读取 URL。格式以文件头魔数为准，白名单外
   * 一律 415；扩展名取自嗅探出的真实 mimetype，与 GET 侧白名单同源。
   */
  async save(file: UploadedImage): Promise<StoredUpload> {
    const mimetype = sniffImageMimetype(file.buffer);
    const ext = ALLOWED_IMAGE_TYPES[mimetype ?? ''];
    if (!mimetype || !ext) throw err.uploadTypeUnsupported();

    const id = `${newId()}.${ext}`;
    return this.storage.save(id, file.buffer, mimetype);
  }

  /**
   * 文件名的读取定位：先过白名单（`..`、编码斜杠、绝对路径在这一层就被
   * 挡下），再交由驱动给出落盘路径（local）或 CDN 地址（s3）。
   */
  async resolve(filename: string): Promise<UploadReadTarget> {
    if (!UPLOAD_FILENAME_PATTERN.test(filename)) throw err.notFound();
    return this.storage.resolve(filename);
  }
}

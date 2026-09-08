import { Injectable, OnModuleInit } from '@nestjs/common';
import { mkdir, stat, writeFile } from 'fs/promises';
import { join } from 'path';
import { err } from '../common/errors/business.exception';
import { newId } from '../common/utils/id.util';
import {
  ALLOWED_IMAGE_TYPES,
  UPLOAD_FILENAME_PATTERN,
  UPLOAD_ROOT,
  UploadedImage,
  sniffImageMimetype,
} from './uploads.storage';

/** 落盘结果：id 即文件名，url 为带版本前缀的读取路径。 */
export interface StoredUpload {
  id: string;
  url: string;
}

/**
 * 图片上传存储（打卡配图链路）：内存缓冲的 multipart 文件按 uuid 落盘到
 * server 根 uploads/，文件名 `${uuid}.${ext}`；扩展名取自服务端校验过的
 * mimetype（不信任客户端文件名），与 GET 侧白名单同源，写入即可读。
 *
 * 〔假设〕MVP 本地磁盘存储，未接 CDN/OSS；迁对象存储时只替换本类的
 * save/resolve 实现，端点契约不变。
 */
@Injectable()
export class UploadsService implements OnModuleInit {
  /** 启动即建目录（multer 走内存存储不建目录，避免首传竞态）。 */
  async onModuleInit(): Promise<void> {
    await mkdir(UPLOAD_ROOT, { recursive: true });
  }

  /**
   * 落盘一张图片，返回文件名与读取 URL。格式以文件头魔数为准（不信
   * 客户端文件名，也不信 multipart 声明的 mimetype），白名单外一律 415。
   */
  async save(file: UploadedImage): Promise<StoredUpload> {
    const ext = ALLOWED_IMAGE_TYPES[sniffImageMimetype(file.buffer) ?? ''];
    if (!ext) throw err.uploadTypeUnsupported();

    const id = `${newId()}.${ext}`;
    await writeFile(join(UPLOAD_ROOT, id), file.buffer);
    return { id, url: `/v1/uploads/${id}` };
  }

  /**
   * 文件名的可读绝对路径：先过白名单（`..`、编码斜杠、绝对路径在这一层
   * 就被挡下），再兜底校验解析结果仍落在 uploads/ 内；不存在或非普通文件
   * 统一 404（不泄露目录结构）。
   */
  async resolve(filename: string): Promise<string> {
    if (!UPLOAD_FILENAME_PATTERN.test(filename)) throw err.notFound();

    const absolute = join(UPLOAD_ROOT, filename);
    const isFile = await stat(absolute)
      .then((s) => s.isFile())
      .catch(() => false);
    if (!absolute.startsWith(UPLOAD_ROOT) || !isFile) throw err.notFound();
    return absolute;
  }
}

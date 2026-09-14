import { Injectable, OnModuleInit } from '@nestjs/common';
import { mkdir, stat, writeFile } from 'fs/promises';
import { join } from 'path';
import { err } from '../common/errors/business.exception';
import { StoredUpload, UPLOAD_ROOT, UploadReadTarget, UploadsStorage } from './uploads.storage';

/**
 * 本地磁盘存储驱动（STORAGE_DRIVER=local，默认）：图片落 server 根 uploads/
 * （已 gitignore，UPLOAD_DIR 供测试隔离覆盖），写入即可读。
 * 仅适合单实例开发/试运行——多实例或容器重建即丢，上线须切 s3（部署手册 §3）。
 */
@Injectable()
export class LocalUploadsStorage implements UploadsStorage, OnModuleInit {
  /** 启动即建目录（multer 走内存存储不建目录，避免首传竞态）。 */
  async onModuleInit(): Promise<void> {
    await mkdir(UPLOAD_ROOT, { recursive: true });
  }

  /** 落盘一张图片，url 为带版本前缀的回源读取路径（GET /v1/uploads/:filename）。 */
  async save(id: string, buffer: Buffer): Promise<StoredUpload> {
    await writeFile(join(UPLOAD_ROOT, id), buffer);
    return { id, url: `/v1/uploads/${id}` };
  }

  /**
   * 文件名的可读绝对路径：兜底校验解析结果仍落在 uploads/ 内（白名单已在
   * service 层挡下 `..`/编码斜杠/绝对路径）；不存在或非普通文件统一 404
   * （不泄露目录结构）。
   */
  async resolve(filename: string): Promise<UploadReadTarget> {
    const absolute = join(UPLOAD_ROOT, filename);
    const isFile = await stat(absolute)
      .then((s) => s.isFile())
      .catch(() => false);
    if (!absolute.startsWith(UPLOAD_ROOT) || !isFile) throw err.notFound();
    return { kind: 'file', path: absolute };
  }
}

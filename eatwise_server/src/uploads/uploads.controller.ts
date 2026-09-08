import {
  CallHandler,
  Controller,
  ExecutionContext,
  Get,
  Injectable,
  NestInterceptor,
  Param,
  Post,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Response } from 'express';
import { Observable } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { UploadsService } from './uploads.service';
import { MAX_UPLOAD_BYTES, UploadedImage } from './uploads.storage';

/**
 * multer 错误 → 业务错误码映射。注册位在 FileInterceptor 之前（第一注册位
 * = 最外层：Nest 拦截器按注册顺序自外向内嵌套），故能捕获其抛出的异常：
 * 超 5MB（LIMIT_FILE_SIZE「File too large」）否则以裸 413 落到全局兜底
 * （code 退化成 INTERNAL_ERROR）；字段名拼错（LIMIT_UNEXPECTED_FILE）
 * 否则是不指明字段的含糊 400。
 */
@Injectable()
export class UploadErrorInterceptor implements NestInterceptor {
  intercept(_: ExecutionContext, next: CallHandler): Observable<unknown> {
    return next.handle().pipe(
      catchError((e: unknown) => {
        const message = (e as Error)?.message ?? '';
        if (message.includes('File too large')) throw err.uploadTooLarge();
        if (message.includes('Unexpected field')) throw err.validation({ file: 'file' });
        throw e;
      }),
    );
  }
}

/**
 * 上传 multipart 选项：内存缓冲 + 5MB 硬上限（超限 multer 抛
 * LIMIT_FILE_SIZE，由 UploadErrorInterceptor 翻成 413 业务码）。
 * 类型不在此处看声明的 mimetype —— 唯一判据是 UploadsService 的
 * 文件头魔数嗅探，避免「声明 image/png 的任意字节」蒙混落盘。
 */
const MULTER_OPTIONS = { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } };

/**
 * 图片上传（打卡配图链路，U1/U2）：
 * POST /v1/uploads —— multipart 字段 file（jpg/png/webp ≤5MB）→ 201 {id, url}；
 * GET /v1/uploads/:filename —— 读图，公开（Image.network 不会带
 * Authorization 头），文件名白名单在 service 层挡下路径穿越。
 */
@Controller('uploads')
export class UploadsController {
  constructor(private readonly uploads: UploadsService) {}

  /** U1 上传图片（需登录：全局 JWT 守卫覆盖，未标 @Public）。 */
  @Post()
  @UseInterceptors(UploadErrorInterceptor, FileInterceptor('file', MULTER_OPTIONS))
  async create(@UploadedFile() file?: UploadedImage) {
    if (!file) throw err.validation({ file: 'file' });
    return this.uploads.save(file);
  }

  /** U2 读取图片：sendFile 按扩展名给 Content-Type；文件名含 uuid → 内容不可变。 */
  @Get(':filename')
  @Public()
  async get(@Param('filename') filename: string, @Res() res: Response): Promise<void> {
    const absolute = await this.uploads.resolve(filename);
    res.sendFile(absolute, { maxAge: '1y', immutable: true });
  }
}

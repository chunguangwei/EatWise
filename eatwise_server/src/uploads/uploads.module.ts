import { Module } from '@nestjs/common';
import { UploadsController } from './uploads.controller';
import { UploadsService } from './uploads.service';

/**
 * 图片上传（打卡配图）：本地磁盘存储（uploads/，已 gitignore）。
 * 无仓储依赖——端点与存储实现都在本模块内，迁 CDN 时只改 UploadsService。
 */
@Module({
  controllers: [UploadsController],
  providers: [UploadsService],
  exports: [UploadsService],
})
export class UploadsModule {}

import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LocalUploadsStorage } from './local-uploads.storage';
import { S3UploadsStorage } from './s3-uploads.storage';
import { UploadsController } from './uploads.controller';
import { UploadsService } from './uploads.service';
import { UPLOADS_STORAGE, UploadsStorage } from './uploads.storage';

/**
 * 图片上传（打卡配图）：存储介质由 STORAGE_DRIVER=local|s3 选择（默认 local
 * 落 uploads/，已 gitignore；s3 走 R2/S3 + CDN，部署手册 §3），组织模式与
 * STORE_DRIVER（InfraModule）一致。s3 模式必需 env 缺失时工厂启动即抛错。
 */
@Module({
  controllers: [UploadsController],
  providers: [
    UploadsService,
    {
      provide: UPLOADS_STORAGE,
      inject: [ConfigService],
      useFactory: (config: ConfigService): UploadsStorage => {
        const driver = config.get<string>('STORAGE_DRIVER', 'local');
        if (driver === 's3') return S3UploadsStorage.fromEnv(config);
        return new LocalUploadsStorage();
      },
    },
  ],
  exports: [UploadsService],
})
export class UploadsModule {}

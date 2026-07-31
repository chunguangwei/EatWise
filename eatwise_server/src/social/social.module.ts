import { Module } from '@nestjs/common';
import { StreakModule } from '../streak/streak.module';
import {
  ContentModerationService,
  StubModerationService,
} from './moderation/content-moderation.service';
import { AdminPostsController } from './admin-posts.controller';
import { SocialController } from './social.controller';
import { SocialService } from './social.service';

@Module({
  imports: [StreakModule],
  controllers: [SocialController, AdminPostsController],
  providers: [
    SocialService,
    // D-17 内容安全：默认桩实现（关键词表模拟三态）；第三方 API 适配器
    // （阿里云/腾讯云，〔待外部确认〕M0 定）实现 ContentModerationService
    // 后替换本 provider 即可。
    { provide: ContentModerationService, useClass: StubModerationService },
  ],
  exports: [SocialService, ContentModerationService],
})
export class SocialModule {}

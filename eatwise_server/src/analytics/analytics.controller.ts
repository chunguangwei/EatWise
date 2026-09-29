import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { Public } from '../auth/public.decorator';
import { AnalyticsEventsDto } from './analytics.dto';
import { AnalyticsService } from './analytics.service';

@Controller('analytics')
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  /**
   * 埋点批量上报（匿名可报：未登录用户的行为采集同样合法，HMAC 匿名化
   * 在客户端完成；客户端裸 Dio 不带 Authorization，故 @Public）。
   * 202 Accepted：接收即返，落盘异步尽力而为。
   */
  @Post('events')
  @Public()
  @HttpCode(202)
  ingest(@Body() dto: AnalyticsEventsDto) {
    return this.analytics.ingest(dto);
  }
}

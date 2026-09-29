import { appendFileSync, mkdirSync } from 'fs';
import { dirname } from 'path';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AnalyticsEventsDto } from './analytics.dto';

/**
 * 埋点采集网关（2026-09-29 补）：客户端 RemoteAnalyticsClient 长期向
 * /v1/analytics/events 批量上报，但服务端始终没有该端点——每批都吃 404
 * 被客户端按「4xx 永久失败」静默丢弃（与 fasting_plans 全断同类事故，
 * 全量契约审计发现）。本实现为最小可用网关：JSONL 追加落盘
 * （`ANALYTICS_LOG_PATH`，默认 data/analytics-events.jsonl），按
 * meta.requestId + event_id 留痕待后续数仓选型消费；落盘失败只记日志，
 * 采集链路永不影响客户端（202 先返）。
 */
@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(private readonly config: ConfigService) {}

  private get logPath(): string {
    return this.config.get<string>('ANALYTICS_LOG_PATH', 'data/analytics-events.jsonl');
  }

  ingest(dto: AnalyticsEventsDto): { accepted: number } {
    const events = dto.data.events;
    if (events.length === 0) return { accepted: 0 };
    try {
      const receivedAt = new Date().toISOString();
      const lines =
        events
          .map((e) =>
            JSON.stringify({
              receivedAt,
              requestId: dto.meta.requestId,
              clientTime: dto.meta.clientTime ?? null,
              ...e,
            }),
          )
          .join('\n') + '\n';
      mkdirSync(dirname(this.logPath), { recursive: true });
      appendFileSync(this.logPath, lines);
    } catch (e) {
      this.logger.error(`埋点落盘失败（已忽略，不影响客户端）: ${e}`);
    }
    return { accepted: events.length };
  }
}

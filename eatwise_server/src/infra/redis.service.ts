import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * Redis 客户端（ioredis，懒连接）：用于验证码/会话、热配置缓存、限流。
 * REDIS_URL 未配置时保持未连接（内存数据层模式）。
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger('Redis');
  private client: Redis | null = null;

  constructor(private readonly config: ConfigService) {}

  get(): Redis {
    if (!this.client) {
      const url = this.config.get<string>('REDIS_URL');
      if (!url) throw new Error('REDIS_URL 未配置');
      this.client = new Redis(url, { lazyConnect: false, maxRetriesPerRequest: 2 });
      this.client.on('error', (e) => this.logger.warn(`redis error: ${e.message}`));
    }
    return this.client;
  }

  async onModuleDestroy() {
    await this.client?.quit();
  }
}

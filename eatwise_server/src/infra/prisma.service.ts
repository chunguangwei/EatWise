import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';

/**
 * Prisma（PostgreSQL ORM）。STORE_DRIVER=prisma 时由 PrismaStore 消费
 * （见 src/common/store/prisma-store.ts）；memory 模式下保持懒连接。
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Prisma');

  constructor(private readonly config: ConfigService) {
    super();
  }

  async onModuleInit() {
    if (!this.config.get('DATABASE_URL')) {
      this.logger.warn('DATABASE_URL 未配置，跳过数据库连接（内存数据层模式）');
      return;
    }
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}

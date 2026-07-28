import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';

/**
 * Prisma（PostgreSQL ORM）。当前各业务 Service 走内存数据层（见 DataStore 注释），
 * 接入真实库时在 DATABASE_URL 配置后将仓储读写替换为 PrismaClient。
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

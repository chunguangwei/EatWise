import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataStore } from '../common/store/data-store';
import { PrismaStore } from '../common/store/prisma-store';
import { MemoryStoreDriver, STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { PrismaService } from './prisma.service';
import { RedisService } from './redis.service';

@Global()
@Module({
  providers: [
    DataStore,
    PrismaService,
    RedisService,
    {
      // STORE_DRIVER=memory|prisma（默认 memory）：选择仓储驱动实现。
      // prisma 模式要求 DATABASE_URL 已配置，否则启动即失败（避免静默丢持久化）。
      provide: STORE_DRIVER,
      inject: [ConfigService, DataStore, PrismaService],
      useFactory: (config: ConfigService, store: DataStore, prisma: PrismaService): StoreDriver => {
        const driver = config.get<string>('STORE_DRIVER', 'memory');
        if (driver === 'prisma') {
          if (!config.get<string>('DATABASE_URL')) {
            throw new Error('STORE_DRIVER=prisma 需要配置 DATABASE_URL');
          }
          return new PrismaStore(prisma);
        }
        return new MemoryStoreDriver(store);
      },
    },
  ],
  exports: [DataStore, PrismaService, RedisService, STORE_DRIVER],
})
export class InfraModule {}

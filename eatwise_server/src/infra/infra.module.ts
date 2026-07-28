import { Global, Module } from '@nestjs/common';
import { DataStore } from '../common/store/data-store';
import { PrismaService } from './prisma.service';
import { RedisService } from './redis.service';

@Global()
@Module({
  providers: [DataStore, PrismaService, RedisService],
  exports: [DataStore, PrismaService, RedisService],
})
export class InfraModule {}

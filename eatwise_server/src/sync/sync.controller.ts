import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { CreateEntryDto, SyncPushDto } from './sync.dto';
import { SyncService } from './sync.service';

@Controller()
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /** E1 创建单条饮食记录（幂等，D-20） */
  @Post('food-entries')
  @HttpCode(200)
  createEntry(@CurrentUser() user: AuthUser, @Body() dto: CreateEntryDto) {
    return this.sync.createEntry(user.userId, dto);
  }

  /** 批量上行同步（规格 §2.3：≤100/批，逐条 ack/nack） */
  @Post('sync/push')
  @HttpCode(200)
  push(@CurrentUser() user: AuthUser, @Body() dto: SyncPushDto) {
    return this.sync.push(user.userId, dto.ops);
  }

  /** 契约 E4 别名：/food-entries/batch-upsert */
  @Post('food-entries/batch-upsert')
  @HttpCode(200)
  batchUpsert(@CurrentUser() user: AuthUser, @Body() dto: SyncPushDto) {
    return this.sync.push(user.userId, dto.ops);
  }

  /** 增量下行（规格 §2.4：syncToken 游标，失效 → 400 INVALID_SYNC_TOKEN 全量重拉） */
  @Get('sync/pull')
  pull(
    @CurrentUser() user: AuthUser,
    @Query('syncToken') syncToken?: string,
    @Query('limit') limit?: string,
  ) {
    return this.sync.pull(user.userId, syncToken, limit ? Number(limit) : 200);
  }

  /** 契约 E6 别名：/sync/food-entries */
  @Get('sync/food-entries')
  pullFoodEntries(
    @CurrentUser() user: AuthUser,
    @Query('syncToken') syncToken?: string,
    @Query('limit') limit?: string,
  ) {
    return this.sync.pull(user.userId, syncToken, limit ? Number(limit) : 200);
  }
}

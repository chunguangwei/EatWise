import { Body, Controller, Get, Headers, HttpCode, Inject, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { isValidTimezone } from '../common/utils/time.util';
import { CreateEntryDto, SyncPushDto } from './sync.dto';
import { SyncService } from './sync.service';

@Controller()
export class SyncController {
  constructor(
    private readonly sync: SyncService,
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
  ) {}

  private async resolveTimezone(user: AuthUser, headerTz?: string): Promise<string> {
    if (headerTz && isValidTimezone(headerTz)) return headerTz;
    const profileTz = (await this.driver.findUserById(user.userId))?.timezone;
    return profileTz && isValidTimezone(profileTz) ? profileTz : 'Asia/Shanghai';
  }

  /** E1 创建单条饮食记录（幂等，D-20） */
  @Post('food-entries')
  @HttpCode(200)
  createEntry(@CurrentUser() user: AuthUser, @Body() dto: CreateEntryDto) {
    return this.sync.createEntry(user.userId, dto);
  }

  /** 批量上行同步（规格 §2.3：≤100/批，逐条 ack/nack） */
  @Post('sync/push')
  @HttpCode(200)
  async push(
    @CurrentUser() user: AuthUser,
    @Body() dto: SyncPushDto,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.sync.push(user.userId, dto.ops, await this.resolveTimezone(user, tz));
  }

  /** 契约 E4 别名：/food-entries/batch-upsert */
  @Post('food-entries/batch-upsert')
  @HttpCode(200)
  async batchUpsert(
    @CurrentUser() user: AuthUser,
    @Body() dto: SyncPushDto,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.sync.push(user.userId, dto.ops, await this.resolveTimezone(user, tz));
  }

  /** 增量下行（规格 §2.4：syncToken 游标，失效 → 400 INVALID_SYNC_TOKEN 全量重拉） */
  @Get('sync/pull')
  async pull(
    @CurrentUser() user: AuthUser,
    @Query('syncToken') syncToken?: string,
    @Query('limit') limit?: string,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.sync.pull(
      user.userId,
      syncToken,
      limit ? Number(limit) : 200,
      await this.resolveTimezone(user, tz),
    );
  }

  /** 契约 E6 别名：/sync/food-entries */
  @Get('sync/food-entries')
  async pullFoodEntries(
    @CurrentUser() user: AuthUser,
    @Query('syncToken') syncToken?: string,
    @Query('limit') limit?: string,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.sync.pull(
      user.userId,
      syncToken,
      limit ? Number(limit) : 200,
      await this.resolveTimezone(user, tz),
    );
  }
}

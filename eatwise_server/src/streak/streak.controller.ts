import { Body, Controller, Get, Headers, HttpCode, Inject, Post } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { MakeupDto } from './streak.dto';
import { StreakService } from './streak.service';

@Controller('streak')
export class StreakController {
  constructor(
    private readonly streak: StreakService,
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
  ) {}

  /** S1 当前 streak、历史最长、里程碑、补签卡状态 */
  @Get()
  async get(@CurrentUser() user: AuthUser, @Headers('x-timezone') tz?: string) {
    const zone =
      tz ?? (await this.driver.findUserById(user.userId))?.timezone ?? 'Asia/Shanghai';
    const entity = await this.streak.recompute(user.userId);
    return this.streak.streakView(entity, zone);
  }

  /** S2 使用补签卡补签（D-12） */
  @Post('makeup')
  @HttpCode(200)
  makeUp(@CurrentUser() user: AuthUser, @Body() dto: MakeupDto) {
    return this.streak.makeUp(user.userId, dto.clientRequestId, dto.date);
  }

  /** S3 里程碑达成列表 */
  @Get('milestones')
  async milestones(@CurrentUser() user: AuthUser) {
    const entity = await this.streak.getOrCreate(user.userId);
    return {
      items: Object.entries(entity.milestones).map(([days, achievedAt]) => ({
        days: Number(days),
        achievedAt,
      })),
    };
  }
}

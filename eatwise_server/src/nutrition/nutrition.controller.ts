import { Controller, Get, Headers, Inject, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { isValidTimezone, localDateOf } from '../common/utils/time.util';
import { NutritionService } from './nutrition.service';

@Controller('nutrition')
export class NutritionController {
  constructor(
    private readonly nutrition: NutritionService,
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
  ) {}

  /** N1 当日聚合 + 信号灯（当日无记录返回 hasData: false） */
  @Get('daily')
  async daily(
    @CurrentUser() user: AuthUser,
    @Query('date') date?: string,
    @Headers('x-timezone') headerTz?: string,
  ) {
    const account = await this.driver.findUserById(user.userId);
    // 非法 X-Timezone 不 500（Intl.RangeError）：回退 profile，同 fasting 口径（走查）
    const tz =
      headerTz && isValidTimezone(headerTz)
        ? headerTz
        : account?.timezone && isValidTimezone(account.timezone)
          ? account.timezone
          : 'Asia/Shanghai';
    return this.nutrition.daily(user.userId, date ?? localDateOf(new Date(), tz), tz);
  }
}

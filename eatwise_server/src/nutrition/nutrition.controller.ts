import { Controller, Get, Headers, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { DataStore } from '../common/store/data-store';
import { localDateOf } from '../common/utils/time.util';
import { NutritionService } from './nutrition.service';

@Controller('nutrition')
export class NutritionController {
  constructor(
    private readonly nutrition: NutritionService,
    private readonly store: DataStore,
  ) {}

  /** N1 当日聚合 + 信号灯（当日无记录返回 hasData: false） */
  @Get('daily')
  daily(
    @CurrentUser() user: AuthUser,
    @Query('date') date?: string,
    @Headers('x-timezone') headerTz?: string,
  ) {
    const tz = headerTz ?? this.store.users.get(user.userId)?.timezone ?? 'Asia/Shanghai';
    return this.nutrition.daily(user.userId, date ?? localDateOf(new Date(), tz), tz);
  }
}

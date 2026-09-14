import { Body, Controller, Get, Headers, HttpCode, Inject, Post, Put } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { isValidTimezone } from '../common/utils/time.util';
import { EndFastingDto, ExtendFastingDto, PutPlanDto } from './fasting.dto';
import { FastingService } from './fasting.service';

@Controller()
export class FastingController {
  constructor(
    private readonly fasting: FastingService,
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
  ) {}

  private async tz(user: AuthUser, headerTz?: string): Promise<string> {
    // 非法 X-Timezone 不 500（Intl.RangeError）：回退用户 profile 时区，profile 亦非法则兜底
    if (headerTz && isValidTimezone(headerTz)) return headerTz;
    const profileTz = (await this.driver.findUserById(user.userId))?.timezone;
    return profileTz && isValidTimezone(profileTz) ? profileTz : 'Asia/Shanghai';
  }

  /** P3 当前方案（含 pending 更换） */
  @Get('fasting-plans/current')
  async getCurrentPlan(@CurrentUser() user: AuthUser, @Headers('x-timezone') tz?: string) {
    const plan = await this.fasting.getCurrentPlan(user.userId, await this.tz(user, tz));
    const pending =
      (await this.driver.listFastingPlansByUser(user.userId)).find((p) => p.status === 'pending') ??
      null;
    return {
      current: {
        id: plan.id,
        planType: plan.planType,
        eatingWindow: { start: plan.eatingWindowStart, end: plan.eatingWindowEnd },
        effectiveDate: plan.effectiveDate,
        status: plan.status,
      },
      pending,
    };
  }

  /** P4 一键启动/更换方案，次日 0 点本地生效（D-06） */
  @Put('fasting-plans/current')
  async putCurrentPlan(
    @CurrentUser() user: AuthUser,
    @Body() dto: PutPlanDto,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.fasting.putCurrentPlan(
      user.userId,
      await this.tz(user, tz),
      dto.planType,
      dto.eatingWindow.start,
      dto.eatingWindow.end,
    );
  }

  /** F1 当前断食状态 */
  @Get('fasting/status')
  async getStatus(@CurrentUser() user: AuthUser, @Headers('x-timezone') tz?: string) {
    return this.fasting.getStatus(user.userId, await this.tz(user, tz));
  }

  /** F2 手动结束断食上报 */
  @Post('fasting/end')
  @HttpCode(200)
  end(@CurrentUser() user: AuthUser, @Body() dto: EndFastingDto) {
    return this.fasting.endFast(
      user.userId,
      dto.clientRequestId,
      dto.recordId,
      new Date(dto.endedAt),
    );
  }

  /** F3 延长上报（D-10） */
  @Post('fasting/extend')
  @HttpCode(200)
  extend(@CurrentUser() user: AuthUser, @Body() dto: ExtendFastingDto) {
    return this.fasting.extend(user.userId, dto.clientRequestId, dto.recordId, dto.extendMinutes);
  }
}

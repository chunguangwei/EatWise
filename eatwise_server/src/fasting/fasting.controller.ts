import { Body, Controller, Get, Headers, HttpCode, Post, Put } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { DataStore } from '../common/store/data-store';
import { EndFastingDto, ExtendFastingDto, PutPlanDto } from './fasting.dto';
import { FastingService } from './fasting.service';

@Controller()
export class FastingController {
  constructor(
    private readonly fasting: FastingService,
    private readonly store: DataStore,
  ) {}

  private tz(user: AuthUser, headerTz?: string): string {
    return headerTz || this.store.users.get(user.userId)?.timezone || 'Asia/Shanghai';
  }

  /** P3 当前方案（含 pending 更换） */
  @Get('fasting-plans/current')
  getCurrentPlan(@CurrentUser() user: AuthUser, @Headers('x-timezone') tz?: string) {
    const plan = this.fasting.getCurrentPlan(user.userId, this.tz(user, tz));
    return {
      current: {
        id: plan.id,
        planType: plan.planType,
        eatingWindow: { start: plan.eatingWindowStart, end: plan.eatingWindowEnd },
        effectiveDate: plan.effectiveDate,
        status: plan.status,
      },
      pending:
        [...this.store.fastingPlans.values()].find(
          (p) => p.userId === user.userId && p.status === 'pending',
        ) ?? null,
    };
  }

  /** P4 一键启动/更换方案，次日 0 点本地生效（D-06） */
  @Put('fasting-plans/current')
  putCurrentPlan(
    @CurrentUser() user: AuthUser,
    @Body() dto: PutPlanDto,
    @Headers('x-timezone') tz?: string,
  ) {
    return this.fasting.putCurrentPlan(
      user.userId,
      this.tz(user, tz),
      dto.planType,
      dto.eatingWindow.start,
      dto.eatingWindow.end,
    );
  }

  /** F1 当前断食状态 */
  @Get('fasting/status')
  getStatus(@CurrentUser() user: AuthUser, @Headers('x-timezone') tz?: string) {
    return this.fasting.getStatus(user.userId, this.tz(user, tz));
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

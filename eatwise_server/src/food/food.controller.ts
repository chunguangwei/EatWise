import { Body, Controller, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { err } from '../common/errors/business.exception';
import { EstimateService } from '../llm/estimate.service';
import { UserThrottlerGuard } from '../llm/user-throttler.guard';
import { BarcodeService } from './barcode/barcode.service';
import { FoodCandidateStatus } from '../common/store/data-store';
import { ContributeFoodDto, CreateCustomFoodDto, EstimateFoodDto } from './food.dto';
import { FoodService } from './food.service';

const CONTRIBUTION_STATUSES: FoodCandidateStatus[] = ['pending', 'approved', 'rejected'];

@Controller('foods')
export class FoodController {
  constructor(
    private readonly food: FoodService,
    private readonly estimate: EstimateService,
    private readonly barcode: BarcodeService,
  ) {}

  /** K1 双语搜索（D-16）：内置库优先，个人自定义食物排后并标注 isCustom */
  @Get('search')
  search(
    @CurrentUser() user: AuthUser,
    @Query('q') q = '',
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.food.search(q, limit ? Number(limit) : 20, cursor, user.userId);
  }

  /** K2 按 id 批量取（离线缓存校验/详情），≤200 个〔假设〕；自定义食物仅创建者可见 */
  @Post('batch-get')
  @HttpCode(200)
  batchGet(@CurrentUser() user: AuthUser, @Body('ids') ids: string[] = []) {
    if (ids.length > 200) throw err.validation({ ids: 'at most 200 ids' });
    const items = ids
      .map((id) => this.food.getById(id, user.userId))
      .filter((f): f is NonNullable<typeof f> => Boolean(f));
    return { items };
  }

  /**
   * LLM 营养估算（供应商可插拔，LLM_PROVIDER 配置）。估算值仅作「估算」标记使用。
   * 限流〔假设〕每用户 10 次/分钟；未配置供应商时返回 ESTIMATE_UNAVAILABLE，客户端降级手动填写。
   */
  @Post('estimate')
  @HttpCode(200)
  @UseGuards(UserThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  estimateFood(@Body() dto: EstimateFoodDto) {
    return this.estimate.estimate(dto.name, dto.description);
  }

  /** 包装食品条码查询（OFF 代理；未命中 404 FOOD_BARCODE_NOT_FOUND，客户端降级） */
  @Get('barcode/:code')
  lookupBarcode(@Param('code') code: string) {
    return this.barcode.lookup(code);
  }

  /** 创建用户自定义食物（个人库，仅创建者可见，参与 K1 搜索；幂等 clientRequestId） */
  @Post('custom')
  @HttpCode(200)
  createCustom(@CurrentUser() user: AuthUser, @Body() dto: CreateCustomFoodDto) {
    return this.food.createCustomFood(user.userId, dto);
  }

  /**
   * 贡献自定义食物到共享库（食物库扩充第三层）：仅创建者可贡献，幂等 clientRequestId；
   * 食物名过机审（D-17 先审后发）：rejected 拒收，manual/approved 入 pending 审核池。
   */
  @Post('custom/:id/contribute')
  @HttpCode(200)
  contribute(
    @CurrentUser() user: AuthUser,
    @Param('id') foodId: string,
    @Body() dto: ContributeFoodDto,
  ) {
    return this.food.contributeCustomFood(user.userId, foodId, dto);
  }

  /**
   * 我的贡献列表（众包状态批量查询）：只返回本人候选，
   * ?status=pending|approved|rejected（缺省全部），页码分页（pageSize ≤50）。
   */
  @Get('contributions')
  contributions(
    @CurrentUser() user: AuthUser,
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('pageSize') pageSize?: string,
  ) {
    let filter: FoodCandidateStatus | undefined;
    if (status) {
      if (!CONTRIBUTION_STATUSES.includes(status as FoodCandidateStatus)) {
        throw err.validation({ status: 'must be pending|approved|rejected' });
      }
      filter = status as FoodCandidateStatus;
    }
    const page1 = Math.max(1, Number(page ?? 1) || 1);
    const size = Math.min(50, Math.max(1, Number(pageSize ?? 20) || 20));
    return this.food.findContributionsByUser(user.userId, filter, page1, size);
  }
}

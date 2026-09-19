import { Body, Controller, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { UserAdminGuard } from '../admin/user-admin.guard';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { err } from '../common/errors/business.exception';
import { FoodCandidateStatus } from '../common/store/data-store';
import { ReviewFoodCandidateDto } from './food.dto';
import { FoodService } from './food.service';

const VALID_STATUS: FoodCandidateStatus[] = ['pending', 'approved', 'rejected'];

/**
 * 移动端审批中心（用户 JWT 体系，role=admin 的用户）：与管理端
 * /v1/admin/food-candidates 同一审核池、同一 FoodService 口径（含驳回级联清理）。
 * 鉴权：全局 JwtAuthGuard（用户 accessToken）+ UserAdminGuard（User.role=='admin'）；
 * 匿名 401，普通用户 403。审核留痕 reviewedBy=用户 id。
 */
@UseGuards(UserAdminGuard)
@Controller('moderation/food-candidates')
export class ModerationFoodController {
  constructor(private readonly food: FoodService) {}

  /** 候选队列：?status=pending|approved|rejected（缺省全部），游标分页（同管理端口径） */
  @Get()
  list(
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    let filter: FoodCandidateStatus | undefined;
    if (status) {
      if (!VALID_STATUS.includes(status as FoodCandidateStatus)) {
        throw err.validation({ status: 'must be pending|approved|rejected' });
      }
      filter = status as FoodCandidateStatus;
    }
    return this.food.listFoodCandidates(filter, limit ? Number(limit) : 20, cursor);
  }

  /** 审核：approve 晋升共享库 / reject 退回（幂等）+ 级联清理；留痕 reviewedBy=当前用户 id */
  @Post(':id/review')
  @HttpCode(200)
  review(
    @Param('id') candidateId: string,
    @Body() dto: ReviewFoodCandidateDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.food.reviewFoodCandidate(candidateId, dto, user.userId);
  }
}

import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { AdminAuthGuard } from '../admin/admin-auth.guard';
import { AdminRole } from '../admin/admin-role.decorator';
import { CurrentAdmin } from '../admin/current-admin.decorator';
import { AdminRequestContext } from '../admin/admin-auth.guard';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { FoodCandidateStatus } from '../common/store/data-store';
import { ReviewFoodCandidateDto } from './food.dto';
import { FoodService } from './food.service';

const VALID_STATUS: FoodCandidateStatus[] = ['pending', 'approved', 'rejected'];

/**
 * 管理端：共享食物候选审核池（食物库扩充第三层）。
 * 鉴权：AdminAuthGuard（管理员 JWT 或 x-admin-token 兜底）+ @AdminRole('reviewer')
 * —— reviewer / admin 均可审核（角色矩阵见 admin-role.decorator.ts）。
 */
@Public()
@UseGuards(AdminAuthGuard)
@AdminRole('reviewer')
@Controller('admin/food-candidates')
export class AdminFoodController {
  constructor(private readonly food: FoodService) {}

  /** 审核队列：?status=pending|approved|rejected（缺省全部），游标分页 */
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

  /** 审核：approve 晋升共享库（source=community 全用户可见）/ reject 退回（创建者仍可见）；留痕 reviewedBy=管理员账号 id（token 兜底为 null） */
  @Post(':id/review')
  @HttpCode(200)
  review(
    @Param('id') candidateId: string,
    @Body() dto: ReviewFoodCandidateDto,
    @CurrentAdmin() admin: AdminRequestContext,
  ) {
    return this.food.reviewFoodCandidate(candidateId, dto, admin.id);
  }

  /** 删除审核内容：候选行 + 食物行/记录级联（同移动端审批中心口径；reviewer/admin 均可） */
  @Delete(':id')
  @HttpCode(200)
  remove(@Param('id') candidateId: string) {
    return this.food.deleteFoodCandidate(candidateId);
  }
}

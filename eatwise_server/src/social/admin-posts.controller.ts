import { Body, Controller, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { AdminAuthGuard } from '../admin/admin-auth.guard';
import { AdminRole } from '../admin/admin-role.decorator';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { ReviewPostDto } from './social.dto';
import { AdminPostFilter, SocialService } from './social.service';

const VALID_STATUS: AdminPostFilter[] = ['pending', 'approved', 'rejected', 'reported'];

/**
 * 管理端：社区打卡审核队列（先审后发 D-17 的人工侧）。
 * 鉴权与 /v1/admin/food-candidates 一致：AdminAuthGuard（管理员 JWT 或
 * x-admin-token 兜底）+ @AdminRole('reviewer') —— reviewer / admin 均可审核。
 */
@Public()
@UseGuards(AdminAuthGuard)
@AdminRole('reviewer')
@Controller('admin/posts')
export class AdminPostsController {
  constructor(private readonly social: SocialService) {}

  /** 审核队列：?status=pending|approved|rejected|reported（缺省全部），游标分页 */
  @Get()
  list(
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    let filter: AdminPostFilter | undefined;
    if (status) {
      if (!VALID_STATUS.includes(status as AdminPostFilter)) {
        throw err.validation({ status: 'must be pending|approved|rejected|reported' });
      }
      filter = status as AdminPostFilter;
    }
    return this.social.adminList(filter, limit ? Number(limit) : 20, cursor);
  }

  /** 审核：approve 上架/恢复（pending/rejected/reported）/ reject 下架（pending/approved，附原因） */
  @Post(':id/review')
  @HttpCode(200)
  review(@Param('id') postId: string, @Body() dto: ReviewPostDto) {
    return this.social.adminReview(postId, dto);
  }
}

import { Body, Controller, Get, Headers, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { ReviewPostDto } from './social.dto';
import { AdminPostFilter, SocialService } from './social.service';

const VALID_STATUS: AdminPostFilter[] = ['pending', 'approved', 'rejected', 'reported'];

/**
 * 管理端：社区打卡审核队列（先审后发 D-17 的人工侧）。
 * 保护与 /v1/admin/food-candidates 一致〔假设〕：header `x-admin-token`
 * 须匹配 env `ADMIN_TOKEN`；env 未配置时一律 404，token 不匹配 401。
 * 正式运营后台接入后应替换为管理员账号 + RBAC。
 */
@Public()
@Controller('admin/posts')
export class AdminPostsController {
  constructor(
    private readonly social: SocialService,
    private readonly config: ConfigService,
  ) {}

  /** 审核队列：?status=pending|approved|rejected|reported（缺省全部），游标分页 */
  @Get()
  list(
    @Headers('x-admin-token') token: string | undefined,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    this.checkToken(token);
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
  review(
    @Headers('x-admin-token') token: string | undefined,
    @Param('id') postId: string,
    @Body() dto: ReviewPostDto,
  ) {
    this.checkToken(token);
    return this.social.adminReview(postId, dto);
  }

  private checkToken(token: string | undefined) {
    const expected = this.config.get<string>('ADMIN_TOKEN');
    if (!expected) throw err.notFound(); // 〔假设〕未配置 ADMIN_TOKEN 时管理端整体关闭
    if (token !== expected) throw err.tokenInvalid();
  }
}

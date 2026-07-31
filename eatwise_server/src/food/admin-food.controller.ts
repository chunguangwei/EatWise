import { Body, Controller, Get, Headers, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { FoodCandidateStatus } from '../common/store/data-store';
import { ReviewFoodCandidateDto } from './food.dto';
import { FoodService } from './food.service';

const VALID_STATUS: FoodCandidateStatus[] = ['pending', 'approved', 'rejected'];

/**
 * 管理端：共享食物候选审核池（食物库扩充第三层）。
 * 简单保护〔假设〕：header `x-admin-token` 须匹配 env `ADMIN_TOKEN`；
 * env 未配置时一律 404（不暴露端点存在性），token 不匹配 401。
 * 正式运营后台接入后应替换为管理员账号 + RBAC。
 */
@Public()
@Controller('admin/food-candidates')
export class AdminFoodController {
  constructor(
    private readonly food: FoodService,
    private readonly config: ConfigService,
  ) {}

  /** 审核队列：?status=pending|approved|rejected（缺省全部），游标分页 */
  @Get()
  list(
    @Headers('x-admin-token') token: string | undefined,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    this.checkToken(token);
    let filter: FoodCandidateStatus | undefined;
    if (status) {
      if (!VALID_STATUS.includes(status as FoodCandidateStatus)) {
        throw err.validation({ status: 'must be pending|approved|rejected' });
      }
      filter = status as FoodCandidateStatus;
    }
    return this.food.listFoodCandidates(filter, limit ? Number(limit) : 20, cursor);
  }

  /** 审核：approve 晋升共享库（source=community 全用户可见）/ reject 退回（创建者仍可见） */
  @Post(':id/review')
  @HttpCode(200)
  review(
    @Headers('x-admin-token') token: string | undefined,
    @Param('id') candidateId: string,
    @Body() dto: ReviewFoodCandidateDto,
  ) {
    this.checkToken(token);
    return this.food.reviewFoodCandidate(candidateId, dto);
  }

  private checkToken(token: string | undefined) {
    const expected = this.config.get<string>('ADMIN_TOKEN');
    if (!expected) throw err.notFound(); // 〔假设〕未配置 ADMIN_TOKEN 时管理端整体关闭
    if (token !== expected) throw err.tokenInvalid();
  }
}

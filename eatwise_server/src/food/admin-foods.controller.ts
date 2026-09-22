import { Controller, Delete, Get, HttpCode, Param, Query, UseGuards } from '@nestjs/common';
import { AdminAuthGuard } from '../admin/admin-auth.guard';
import { AdminRole } from '../admin/admin-role.decorator';
import { Public } from '../auth/public.decorator';
import { FoodService } from './food.service';

/**
 * 管理端：食物库管理（搜索 + 删除同名重复条目）。
 * 鉴权：AdminAuthGuard（管理员 JWT 或 x-admin-token 兜底）；类级 @AdminRole('reviewer')
 * ——搜索 reviewer / admin 均可；删除 @AdminRole('admin')（审核员不可删，角色矩阵
 * 见 admin-role.decorator.ts）。删除为软删 tombstone + 跨用户级联软删饮食记录，
 * pending 审核候选关联 → 409 FOOD_UNDER_REVIEW（口径见 FoodService.adminDeleteFood）。
 */
@Public()
@UseGuards(AdminAuthGuard)
@AdminRole('reviewer')
@Controller('admin/foods')
export class AdminFoodsController {
  constructor(private readonly food: FoodService) {}

  /** 食物库搜索：?q=关键词（共享/内置 + 全部用户自定义），游标分页 */
  @Get()
  search(@Query('q') q?: string, @Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    return this.food.adminSearchFoods(q ?? '', limit ? Number(limit) : 20, cursor);
  }

  /** 删除食物（仅 admin）：软删 + 级联软删引用饮食记录；缺行/已删 404，审核中 409 */
  @Delete(':id')
  @HttpCode(200)
  @AdminRole('admin')
  remove(@Param('id') foodId: string) {
    return this.food.adminDeleteFood(foodId);
  }
}

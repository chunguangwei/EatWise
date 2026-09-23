import { Controller, Delete, HttpCode, Param, UseGuards } from '@nestjs/common';
import { UserAdminGuard } from '../admin/user-admin.guard';
import { FoodService } from './food.service';

/**
 * 移动端管理员食物库操作（用户 JWT 体系，role=admin 的用户）：
 * 与管理台 /v1/admin/foods 删除**同一 FoodService.adminDeleteFood 口径**
 * （软删任意来源食物行 + 跨用户级联 tombstone 饮食记录；pending 审核候选
 * 关联 409 FOOD_UNDER_REVIEW；行不存在/已删 404）——逻辑不落第二份，
 * 两端不漂移。
 * 鉴权：全局 JwtAuthGuard（用户 accessToken）+ UserAdminGuard（User.role=='admin'）；
 * 匿名 401，普通用户 403。
 */
@UseGuards(UserAdminGuard)
@Controller('moderation/foods')
export class ModerationFoodsController {
  constructor(private readonly food: FoodService) {}

  /** 删除食物（管理员）：软删 + 级联软删引用记录；缺行/已删 404，审核中 409 */
  @Delete(':id')
  @HttpCode(200)
  remove(@Param('id') foodId: string) {
    return this.food.adminDeleteFood(foodId);
  }
}

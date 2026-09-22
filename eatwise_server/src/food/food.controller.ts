import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { err } from '../common/errors/business.exception';
import { BarcodeService } from './barcode/barcode.service';
import { FoodCandidateStatus } from '../common/store/data-store';
import {
  BatchGetFoodsDto,
  ContributeFoodDto,
  CreateCustomFoodDto,
  CreateFoodCorrectionDto,
  UpdateCustomFoodDto,
} from './food.dto';
import { FoodService } from './food.service';

const CONTRIBUTION_STATUSES: FoodCandidateStatus[] = ['pending', 'approved', 'rejected'];

@Controller('foods')
export class FoodController {
  constructor(
    private readonly food: FoodService,
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
  async batchGet(@CurrentUser() user: AuthUser, @Body() dto: BatchGetFoodsDto) {
    const found = await Promise.all(dto.ids.map((id) => this.food.getById(id, user.userId)));
    return { items: found.filter((f): f is NonNullable<typeof f> => Boolean(f)) };
  }

  /**
   * 包装食品条码查询：先查自有共享库（条码众包上架商品，source=eatwise），
   * 未命中再代理 OpenFoodFacts（source=openfoodfacts）；均未命中
   * 404 FOOD_BARCODE_NOT_FOUND（客户端降级手动补录 → 众包贡献）。
   */
  @Get('barcode/:code')
  async lookupBarcode(@Param('code') code: string) {
    const own = await this.food.lookupOwnBarcode(code);
    if (own) return own;
    return this.barcode.lookup(code);
  }

  /** 创建用户自定义食物（个人库，仅创建者可见，参与 K1 搜索；幂等 clientRequestId） */
  @Post('custom')
  @HttpCode(200)
  createCustom(@CurrentUser() user: AuthUser, @Body() dto: CreateCustomFoodDto) {
    return this.food.createCustomFood(user.userId, dto);
  }

  /**
   * 更新自定义食物（个人库编辑；LWW 无幂等键——重放同值无害）。
   * 仅创建者可改（他人/共享/已删 → 404，不泄露存在性）；校验口径同创建。
   */
  @Patch('custom/:id')
  @HttpCode(200)
  updateCustom(
    @CurrentUser() user: AuthUser,
    @Param('id') foodId: string,
    @Body() dto: UpdateCustomFoodDto,
  ) {
    return this.food.updateCustomFood(user.userId, foodId, dto);
  }

  /**
   * 删除自定义食物（软删 tombstone，读路径即时隐藏）：仅创建者可删；
   * 已提交共享审核（pending 候选）→ 409 FOOD_UNDER_REVIEW（先撤销/等审核落定）；
   * 级联软删本人引用该食物的饮食记录（sync/pull 下行 tombstone 清其它设备）。幂等重删 404。
   */
  @Delete('custom/:id')
  @HttpCode(200)
  deleteCustom(@CurrentUser() user: AuthUser, @Param('id') foodId: string) {
    return this.food.deleteCustomFood(user.userId, foodId);
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
   * 已有共享食物的数据纠错（食物详情页「数据有误？」入口）：建议名称/每 100g 营养
   * 入审核池（kind=correction），approve 后应用到共享食物行；幂等 clientRequestId；
   * 同人同食物已有 pending 纠错幂等返回原候选。
   */
  @Post(':id/correction')
  @HttpCode(200)
  correct(
    @CurrentUser() user: AuthUser,
    @Param('id') foodId: string,
    @Body() dto: CreateFoodCorrectionDto,
  ) {
    return this.food.createFoodCorrection(user.userId, foodId, dto);
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

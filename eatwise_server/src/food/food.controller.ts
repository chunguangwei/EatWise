import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { FoodService } from './food.service';

@Controller('foods')
export class FoodController {
  constructor(private readonly food: FoodService) {}

  /** K1 双语搜索（D-16） */
  @Get('search')
  search(@Query('q') q = '', @Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    return this.food.search(q, limit ? Number(limit) : 20, cursor);
  }

  /** K2 按 id 批量取（离线缓存校验/详情），≤200 个〔假设〕 */
  @Post('batch-get')
  @HttpCode(200)
  batchGet(@Body('ids') ids: string[] = []) {
    if (ids.length > 200) throw err.validation({ ids: 'at most 200 ids' });
    const items = ids
      .map((id) => this.food.getById(id))
      .filter((f): f is NonNullable<typeof f> => Boolean(f));
    return { items };
  }
}

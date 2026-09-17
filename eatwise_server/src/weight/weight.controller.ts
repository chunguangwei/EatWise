import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { CreateWeightLogDto } from './weight.dto';
import { WeightService } from './weight.service';

@Controller('weight-logs')
export class WeightController {
  constructor(private readonly weight: WeightService) {}

  /** 体重记录幂等 upsert（阶段 C：同 userId+date 覆写，clientRequestId 重放返回首次结果） */
  @Post()
  @HttpCode(200)
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateWeightLogDto) {
    return this.weight.upsert(user.userId, dto);
  }

  /** 体重区间查询（含端点，date 升序；from/to 缺省分别为 1970-01-01 / 今天） */
  @Get()
  list(@CurrentUser() user: AuthUser, @Query('from') from?: string, @Query('to') to?: string) {
    return this.weight.list(user.userId, from, to);
  }

  /** 软删（tombstone；重复删除幂等，他人记录 404） */
  @Delete(':id')
  @HttpCode(200)
  remove(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.weight.remove(user.userId, id);
  }
}

import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { CreatePostDto, ReportPostDto } from './social.dto';
import { SocialService } from './social.service';

/** 社区打卡接口（契约 §3.9，C1–C7） */
@Controller('posts')
export class SocialController {
  constructor(private readonly social: SocialService) {}

  /** C1 发布打卡（先审后发 D-17；approved → auditStatus=approved，manual → pending） */
  @Post()
  @HttpCode(200)
  async create(@CurrentUser() user: AuthUser, @Body() dto: CreatePostDto) {
    return await this.social.create(user.userId, dto);
  }

  /** C2 打卡流（游标分页，倒序混排 D-15） */
  @Get('feed')
  async feed(
    @CurrentUser() user: AuthUser,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return await this.social.feed(user.userId, limit ? Number(limit) : 20, cursor);
  }

  /** C3 单帖详情 */
  @Get(':id')
  async getById(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return await this.social.getById(user.userId, id);
  }

  /** C4 删除本人打卡（幂等） */
  @Delete(':id')
  @HttpCode(200)
  async remove(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return await this.social.remove(user.userId, id);
  }

  /** C5 点赞（幂等） */
  @Post(':id/like')
  @HttpCode(200)
  async like(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return await this.social.like(user.userId, id);
  }

  /** C6 取消点赞（幂等） */
  @Delete(':id/like')
  @HttpCode(200)
  async unlike(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return await this.social.unlike(user.userId, id);
  }

  /** C7 举报（幂等，下架转人工复核） */
  @Post(':id/report')
  @HttpCode(200)
  async report(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReportPostDto) {
    return await this.social.report(user.userId, id, dto.reason);
  }
}

import {
  ArrayMaxSize,
  IsArray,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  MaxLength,
} from 'class-validator';

/** C1 发布打卡（契约 §3.9：文字 ≤500 字 + 可选图片 URL） */
export class CreatePostDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsString()
  @Length(1, 500)
  text: string;

  /**
   * 图片 URL 列表（〔假设〕MVP 图片传 URL 占位；正式上传链路
   * POST /uploads/images → 直传 CDN 留 TODO，契约 §3.9 注）。
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(9)
  @IsString({ each: true })
  imageUrls?: string[];

  /**
   * 客户端提示的连续天数（可选）。服务端以自身 streak 权威值（D-12 口径）
   * 覆盖写入 streakDaysAtPost，不信任客户端值。
   */
  @IsOptional()
  linkedStreakDays?: number;
}

/** C7 举报（同用户同帖幂等一次） */
export class ReportPostDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

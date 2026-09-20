import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
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
  /**
   * 匿名发帖：作者身份对非作者查看者遮蔽（服务端视图层抹除 author.id/nickname）。
   */
  @IsOptional()
  @IsBoolean()
  anonymous?: boolean;

  /**
   * 预设头像库索引（客户端常量表 0–7，共 8 套微信/QQ 式默认头像）。
   * 仅 anonymous=true 时有意义；跟帖固定，不随用户资料变。
   */
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(7)
  avatarId?: number;
}

/** C7 举报（同用户同帖幂等一次） */
export class ReportPostDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

/** 管理端审核决定（/v1/admin/posts/:id/review） */
export class ReviewPostDto {
  @IsIn(['approve', 'reject'])
  action: 'approve' | 'reject';

  /** 操作原因（reject 建议填写，透传给作者；approve 可选备注） */
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

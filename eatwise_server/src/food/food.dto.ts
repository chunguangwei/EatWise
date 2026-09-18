import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/** 每 100g 营养（区间与 food.rules 防腐校验一致：kcal ≤900，其余 ≤100） */
export class Per100gDto {
  @IsNumber()
  @Min(0)
  @Max(900)
  kcal: number;

  @IsNumber()
  @Min(0)
  @Max(100)
  proteinG: number;

  @IsNumber()
  @Min(0)
  @Max(100)
  carbG: number;

  @IsNumber()
  @Min(0)
  @Max(100)
  fatG: number;
}

export class CreateCustomFoodDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  nameZh: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  nameEn?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  aliasesZh?: string[];

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  aliasesEn?: string[];

  @ValidateNested()
  @Type(() => Per100gDto)
  per100g: Per100gDto;

  @IsIn(['manual', 'llm-estimate'])
  source: 'manual' | 'llm-estimate';
}

/**
 * 贡献自定义食物到共享库（幂等 clientRequestId）。
 * 条码商品补录（OFF 未命中场景）：额外传 barcode + evidenceImageUrl（包装营养表
 * 佐证照片，先经 POST /v1/uploads 上传）；两者必须成对出现，传了 barcode 即 kind=barcode。
 */
export class ContributeFoodDto {
  @IsUUID('4')
  clientRequestId: string;

  /** 商品条码（EAN-8/13、UPC-A 等：8-14 位纯数字，与 BarcodeService 同口径） */
  @IsOptional()
  @Matches(/^\d{8,14}$/, { message: 'barcode must be 8-14 digits' })
  barcode?: string;

  /** 包装营养表佐证照片 URL（/v1/uploads/xxx 或 CDN URL）；条码贡献必填（审核「对答案」根基） */
  @IsOptional()
  @IsString()
  @MaxLength(500)
  evidenceImageUrl?: string;
}

/** 管理端审核共享食物候选 */
export class ReviewFoodCandidateDto {
  @IsIn(['approve', 'reject'])
  action: 'approve' | 'reject';

  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

/**
 * 已有共享食物的数据纠错（食物详情页「数据有误？」入口，幂等 clientRequestId）。
 * 预填当前值由客户端完成：名称未改传缺省，四项营养值整体提交（区间同自定义食物防腐口径）。
 * approve 后建议值应用到共享食物行（候选 kind=correction，建议值存 suggestion 供审核台与原值对照）。
 */
export class CreateFoodCorrectionDto {
  @IsUUID('4')
  clientRequestId: string;

  /** 建议中文名（未改名缺省；trim 后 1-50 字，过机审） */
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  nameZh?: string;

  /** 建议英文名（未改缺省） */
  @IsOptional()
  @IsString()
  @MaxLength(100)
  nameEn?: string;

  @ValidateNested()
  @Type(() => Per100gDto)
  per100g: Per100gDto;
}

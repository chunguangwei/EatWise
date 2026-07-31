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
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class EstimateFoodDto {
  /** 菜名（trim 后 1-50 字，服务侧再校验） */
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  description?: string;
}

/** 每 100g 营养（区间与 LLM 估算校验一致：kcal ≤900，其余 ≤100） */
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

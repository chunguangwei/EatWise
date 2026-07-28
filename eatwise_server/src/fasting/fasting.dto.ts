import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsString,
  IsUUID,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export class EatingWindowDto {
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  start: string;

  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  end: string;
}

export class PutPlanDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsIn(['14:10', '16:8', '18:6']) // 5:2 仅展示不入库（D-03）
  planType: string;

  @ValidateNested()
  @Type(() => EatingWindowDto)
  eatingWindow: EatingWindowDto;
}

export class EndFastingDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsString()
  @IsNotEmpty()
  recordId: string;

  @IsISO8601()
  endedAt: string;
}

export class ExtendFastingDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsString()
  @IsNotEmpty()
  recordId: string;

  /** 步进 30 分钟、累计 ≤240（D-10） */
  @IsInt()
  @Min(30)
  @Max(240)
  extendMinutes: number;
}

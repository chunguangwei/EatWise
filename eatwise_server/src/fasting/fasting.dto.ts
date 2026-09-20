import { Type } from 'class-transformer';
import {
  IsDefined,
  IsIn,
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsString,
  IsUUID,
  Matches,
  Max,
  Min,
  Validate,
  ValidationArguments,
  ValidatorConstraint,
  ValidatorConstraintInterface,
  ValidateNested,
} from 'class-validator';
import { isValidTimeStr } from '../common/utils/time.util';

export class EatingWindowDto {
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  start: string;

  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  end: string;
}

/** planType → 进食小时数（D-03 入库三档；禁食 = 24 − 进食） */
const EATING_HOURS: Record<string, number> = { '14:10': 10, '16:8': 8, '18:6': 6 };

/**
 * 跨字段校验：进食窗口时长 ((end−start+1440)%1440 分钟，支持跨午夜)
 * 必须等于 planType 对应的进食时长。缺失/格式非法的字段由各自装饰器报错，这里放行避免重复噪声。
 */
@ValidatorConstraint({ name: 'eatingWindowMatchesPlan', async: false })
class EatingWindowMatchesPlanConstraint implements ValidatorConstraintInterface {
  validate(window: EatingWindowDto, args: ValidationArguments): boolean {
    const dto = args.object as PutPlanDto;
    const hours = EATING_HOURS[dto?.planType];
    if (!hours || !window || !isValidTimeStr(window.start) || !isValidTimeStr(window.end)) {
      return true; // 字段级非法由 @IsIn/@Matches 各自报错，避免重复噪声
    }
    const toMins = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
    return (toMins(window.end) - toMins(window.start) + 1440) % 1440 === hours * 60;
  }

  defaultMessage(): string {
    return 'eatingWindow duration must equal planType eating hours (cross-midnight allowed)';
  }
}

export class PutPlanDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsIn(['14:10', '16:8', '18:6']) // 5:2 仅展示不入库（D-03）
  planType: string;

  /** 进食窗口：时长必须与 planType 进食时长一致（允许跨午夜，如 16:8 配 20:00–06:00） */
  @IsDefined() // 缺失时 ValidateNested 会跳过 → controller 解引用 500；显式必填保证 400
  @Validate(EatingWindowMatchesPlanConstraint)
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

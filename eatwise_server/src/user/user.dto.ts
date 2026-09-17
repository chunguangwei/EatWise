import {
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  Validate,
  ValidatorConstraint,
  ValidatorConstraintInterface,
} from 'class-validator';
import { isValidTimezone } from '../common/utils/time.util';

/** IANA 时区名校验（非法名会让 Intl.DateTimeFormat 抛 RangeError，打挂核心端点） */
@ValidatorConstraint({ name: 'isIanaTimezone', async: false })
class IsIanaTimezoneConstraint implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return typeof value === 'string' && isValidTimezone(value);
  }

  defaultMessage(): string {
    return 'timezone must be a valid IANA timezone name';
  }
}

/** U2 修改资料（字段级 LWW）：全部可选；数值字段范围校验，timezone 校验 IANA 合法性 */
export class PatchUserDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  nickname?: string;

  @IsOptional()
  @IsString()
  gender?: string;

  @IsOptional()
  @IsInt()
  @Min(1900)
  @Max(new Date().getUTCFullYear())
  birthYear?: number;

  @IsOptional()
  @IsNumber()
  @Min(50)
  @Max(300)
  heightCm?: number;

  @IsOptional()
  @IsNumber()
  @Min(20)
  @Max(500)
  weightKg?: number;

  @IsOptional()
  @IsString()
  activityLevel?: string;

  @IsOptional()
  @IsString()
  goal?: string;

  @IsOptional()
  @IsString()
  @Validate(IsIanaTimezoneConstraint)
  timezone?: string;

  @IsOptional()
  @IsString()
  locale?: string;

  @IsOptional()
  @IsString()
  themePref?: string;

  @IsOptional()
  @IsObject()
  accessibilityPrefs?: Record<string, unknown>;

  /** 引导状态回写（客户端 onboarding 完成/跳过时上报；枚举校验防脏数据） */
  @IsOptional()
  @IsIn(['none', 'completed', 'skipped'])
  onboardingStatus?: string;
}

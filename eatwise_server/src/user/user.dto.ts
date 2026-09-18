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

/** 减重目标日期校验（阶段 B）：YYYY-MM-DD 真实日期、严格未来（UTC 日粒度）、距今 ≤2 年 */
@ValidatorConstraint({ name: 'isTargetDate', async: false })
class IsTargetDateConstraint implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    if (typeof value !== 'string') return false;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(`${value}T00:00:00.000Z`);
    // 滚入下月的伪日期（如 2026-02-31）拒收
    if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
      return false;
    }
    const now = new Date();
    const todayUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    const maxUtc = Date.UTC(now.getUTCFullYear() + 2, now.getUTCMonth(), now.getUTCDate());
    const t = date.getTime();
    return t > todayUtc && t <= maxUtc;
  }

  defaultMessage(): string {
    return 'targetDate must be a future date (YYYY-MM-DD) within 2 years';
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

  /** 阶段 B 减重目标：目标体重（kg，25–300）；null 表示清空 */
  @IsOptional()
  @IsNumber()
  @Min(25)
  @Max(300)
  targetWeightKg?: number | null;

  /** 阶段 B 减重目标：目标日期（YYYY-MM-DD，未来且 ≤2 年）；null 表示清空 */
  @IsOptional()
  @Validate(IsTargetDateConstraint)
  targetDate?: string | null;

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

  /** D-21 用户级偏好同步包（locale/theme/weightUnit/运动目标 + syncedAt） */
  @IsOptional()
  @IsObject()
  settingsPrefs?: Record<string, unknown>;

  /** 引导状态回写（客户端 onboarding 完成/跳过时上报；枚举校验防脏数据） */
  @IsOptional()
  @IsIn(['none', 'completed', 'skipped'])
  onboardingStatus?: string;
}

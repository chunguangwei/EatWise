import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsISO8601,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export class EntryPayloadDto {
  @IsOptional()
  @IsString()
  id?: string; // serverId（create 时省略）

  @IsOptional()
  @IsISO8601()
  eatenAt?: string;

  @IsOptional()
  @IsString()
  foodId?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.1)
  @Max(5000) // 份量上限〔假设〕
  grams?: number;

  @IsOptional()
  @IsIn(['photo', 'voice', 'frequent', 'manual', 'barcode'])
  inputMethod?: string;

  @IsOptional()
  @IsString()
  photoUrl?: string;

  // ---- waterLog 载荷（entity=waterLog 时使用，与 EntryPayload 二选一）----

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5000) // 单次饮水量上限〔假设〕，与快捷档位 200/300/500 兼容
  amountMl?: number;

  @IsOptional()
  @IsISO8601()
  loggedAt?: string; // 饮水时间（UTC）

  @IsOptional()
  @IsString()
  localDate?: string; // 客户端归属日（yyyy-MM-dd，透传）

  @IsOptional()
  @IsString()
  clientRequestId?: string; // waterLog/exerciseLog delete 兜底定位（create 已上行但 serverId 丢失场景）

  // ---- exerciseLog 载荷（entity=exerciseLog 时使用，与上两者二选一）----

  @IsOptional()
  @IsString()
  typeKey?: string; // 运动类型键（walk/jog/.../summary 活动统计导入）

  @IsOptional()
  @IsInt()
  @Min(0) // 活动统计导入无时长口径为 0
  @Max(1440) // 单日时长上限〔假设〕防误输
  durationMin?: number;

  @IsOptional()
  @IsNumber()
  @Min(0.1)
  @Max(10000) // 单次消耗上限〔假设〕防误输
  kcal?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(200000) // 单日步数上限〔假设〕防误输
  steps?: number;

  @IsOptional()
  @IsIn(['screenshot']) // null=手动录入；'screenshot'=截图识别导入
  source?: string;
}

export class SyncOpDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsIn(['foodEntry', 'waterLog', 'exerciseLog']) // 防腐层覆盖 FoodEntry + WaterLog/ExerciseLog（轻量两态）；fastingRecord/userProfile/fastingPlan 后续接入
  entity: string;

  @IsIn(['create', 'update', 'delete'])
  op: string;

  @IsOptional()
  @IsString()
  serverId?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  baseVersion?: number; // update/delete 必带（LWW 冲突检测）

  @IsOptional()
  @ValidateNested()
  @Type(() => EntryPayloadDto)
  payload?: EntryPayloadDto;
}

export class SyncPushDto {
  @IsArray()
  @ArrayMaxSize(100) // 单批 ≤100 条〔假设〕，超出分批串行
  @ValidateNested({ each: true })
  @Type(() => SyncOpDto)
  ops: SyncOpDto[];
}

export class CreateEntryDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsISO8601()
  eatenAt: string;

  @IsString()
  foodId: string;

  @IsNumber()
  @Min(0.1)
  @Max(5000)
  grams: number;

  @IsIn(['photo', 'voice', 'frequent', 'manual', 'barcode'])
  inputMethod: string;

  @IsOptional()
  @IsString()
  photoUrl?: string;
}

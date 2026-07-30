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
  @IsIn(['photo', 'voice', 'frequent', 'manual'])
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
  clientRequestId?: string; // waterLog delete 兜底定位（create 已上行但 serverId 丢失场景）
}

export class SyncOpDto {
  @IsUUID('4')
  clientRequestId: string;

  @IsIn(['foodEntry', 'waterLog']) // 防腐层覆盖 FoodEntry + WaterLog（轻量两态）；fastingRecord/userProfile/fastingPlan 后续接入
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

  @IsIn(['photo', 'voice', 'frequent', 'manual'])
  inputMethod: string;

  @IsOptional()
  @IsString()
  photoUrl?: string;
}

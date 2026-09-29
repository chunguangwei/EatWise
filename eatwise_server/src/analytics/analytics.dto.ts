import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsDefined,
  IsISO8601,
  IsNotEmpty,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';

/** 单条埋点事件（与客户端 AnalyticsEvent.toJson 契约一致：snake_case 字段） */
export class AnalyticsEventItemDto {
  @IsString()
  @IsNotEmpty()
  event_id: string;

  @IsString()
  @IsNotEmpty()
  event_name: string;

  @IsOptional()
  @IsNumber()
  timestamp?: number;

  @IsOptional()
  @IsString()
  client_date?: string;

  @IsOptional()
  @IsObject()
  common?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  properties?: Record<string, unknown>;
}

export class AnalyticsEventsDataDto {
  @IsDefined() // 缺失时 IsArray 跳过 → 安静收下空包；显式必填保证 400
  @IsArray()
  @ArrayMaxSize(500) // 单批上限〔假设〕，客户端批量远小于此
  @ValidateNested({ each: true })
  @Type(() => AnalyticsEventItemDto)
  events: AnalyticsEventItemDto[];
}

export class AnalyticsEventsMetaDto {
  @IsString()
  @IsNotEmpty()
  requestId: string;

  @IsOptional()
  @IsISO8601()
  clientTime?: string;
}

/** POST /v1/analytics/events 载荷（自建采集网关，契约见埋点规范 §1.3） */
export class AnalyticsEventsDto {
  @IsDefined() // ValidateNested 对 undefined 跳过：缺 data/meta 必须 400
  @ValidateNested()
  @Type(() => AnalyticsEventsDataDto)
  data: AnalyticsEventsDataDto;

  @IsDefined()
  @ValidateNested()
  @Type(() => AnalyticsEventsMetaDto)
  meta: AnalyticsEventsMetaDto;
}

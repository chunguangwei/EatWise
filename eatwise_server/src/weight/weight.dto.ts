import { IsNumber, IsOptional, IsUUID, Matches, Max, Min } from 'class-validator';

/** POST /v1/weight-logs 载荷（阶段 C：幂等 upsert，同 userId+date 覆写） */
export class CreateWeightLogDto {
  @IsUUID('4')
  clientRequestId: string;

  /** 归属日（yyyy-MM-dd，客户端本地口径透传，D-07） */
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  date: string;

  /** 体重（kg；20–300 防误输，与客户端录入口径一致） */
  @IsNumber()
  @Min(20)
  @Max(300)
  weightKg: number;

  /** 体脂率（%，可空；显式 null 表示清除） */
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(70)
  bodyFatPct?: number | null;
}

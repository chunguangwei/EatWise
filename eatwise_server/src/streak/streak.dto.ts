import { IsUUID, Matches } from 'class-validator';

export class MakeupDto {
  @IsUUID('4')
  clientRequestId: string;

  /** 补签的归属日（本地日 YYYY-MM-DD，配合用户 timezone） */
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  date: string;
}

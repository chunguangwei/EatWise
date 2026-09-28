import { Module } from '@nestjs/common';
import { LegalPagesController } from './legal-pages.controller';

/** 法务静态页（/privacy、/terms，匿名公网可访问，App Store 条例要求） */
@Module({
  controllers: [LegalPagesController],
})
export class LegalModule {}

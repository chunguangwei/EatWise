import { Module, forwardRef } from '@nestjs/common';
import { StreakModule } from '../streak/streak.module';
import { FastingController } from './fasting.controller';
import { FastingService } from './fasting.service';

@Module({
  imports: [forwardRef(() => StreakModule)],
  controllers: [FastingController],
  providers: [FastingService],
  exports: [FastingService],
})
export class FastingModule {}

import { Module } from '@nestjs/common';
import { NutritionModule } from '../nutrition/nutrition.module';
import { StreakModule } from '../streak/streak.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({
  imports: [NutritionModule, StreakModule],
  controllers: [SyncController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}

import { Module } from '@nestjs/common';
import { LlmModule } from '../llm/llm.module';
import { FoodController } from './food.controller';
import { FoodService } from './food.service';

@Module({
  imports: [LlmModule],
  controllers: [FoodController],
  providers: [FoodService],
  exports: [FoodService],
})
export class FoodModule {}

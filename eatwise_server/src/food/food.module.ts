import { Module } from '@nestjs/common';
import { SocialModule } from '../social/social.module';
import { AdminFoodController } from './admin-food.controller';
import { AdminFoodsController } from './admin-foods.controller';
import { BarcodeService } from './barcode/barcode.service';
import { FoodController } from './food.controller';
import { ModerationFoodController } from './moderation-food.controller';
import { ModerationFoodsController } from './moderation-foods.controller';
import { FoodService } from './food.service';

@Module({
  // SocialModule 导出 ContentModerationService（D-17 三态机审抽象，贡献食物名复用）
  imports: [SocialModule],
  controllers: [
    FoodController,
    AdminFoodController,
    AdminFoodsController,
    ModerationFoodController,
    ModerationFoodsController,
  ],
  providers: [FoodService, BarcodeService],
  exports: [FoodService],
})
export class FoodModule {}

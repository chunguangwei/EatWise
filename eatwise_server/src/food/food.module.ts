import { Module } from '@nestjs/common';
import { SocialModule } from '../social/social.module';
import { AdminFoodController } from './admin-food.controller';
import { BarcodeService } from './barcode/barcode.service';
import { FoodController } from './food.controller';
import { FoodService } from './food.service';

@Module({
  // SocialModule 导出 ContentModerationService（D-17 三态机审抽象，贡献食物名复用）
  imports: [SocialModule],
  controllers: [FoodController, AdminFoodController],
  providers: [FoodService, BarcodeService],
  exports: [FoodService],
})
export class FoodModule {}

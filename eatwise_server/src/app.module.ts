import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_FILTER, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppVersionModule } from './app-version/app-version.module';
import { AuthModule } from './auth/auth.module';
import { GlobalExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { FastingModule } from './fasting/fasting.module';
import { FoodModule } from './food/food.module';
import { HealthController } from './health/health.controller';
import { InfraModule } from './infra/infra.module';
import { NutritionModule } from './nutrition/nutrition.module';
import { SocialModule } from './social/social.module';
import { StreakModule } from './streak/streak.module';
import { SyncModule } from './sync/sync.module';
import { UserModule } from './user/user.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    // 限流（契约 §6.1，阈值〔假设〕按压测校准）：默认 300 req/min
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 300 }]),
    InfraModule,
    AppVersionModule,
    AuthModule,
    UserModule,
    FastingModule,
    FoodModule,
    NutritionModule,
    SocialModule,
    StreakModule,
    SyncModule,
  ],
  controllers: [HealthController],
  providers: [
    { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
  ],
})
export class AppModule {}

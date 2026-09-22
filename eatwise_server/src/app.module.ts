import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AdminModule } from './admin/admin.module';
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
import { UploadsModule } from './uploads/uploads.module';
import { UserModule } from './user/user.module';
import { WeightModule } from './weight/weight.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    // 限流（契约 §6.1，阈值〔假设〕按压测校准）：默认 300 req/min/IP（trust
    // proxy 取 XFF 真实客户端 IP，见 main.ts）；THROTTLE_LIMIT env 可调，
    // e2e 高频 spec 在其文件内设大值防 429。守卫经 APP_GUARD 全局绑定。
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        throttlers: [{ ttl: 60_000, limit: Number(config.get('THROTTLE_LIMIT', 300)) }],
      }),
    }),
    InfraModule,
    AdminModule,
    AppVersionModule,
    AuthModule,
    UserModule,
    FastingModule,
    FoodModule,
    NutritionModule,
    SocialModule,
    StreakModule,
    SyncModule,
    UploadsModule,
    WeightModule,
  ],
  controllers: [HealthController],
  providers: [
    { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}

import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';

/** 仓库公开占位密钥（.env.example 模板值 / 代码缺省值）——生产用到即等同没配 */
const PLACEHOLDER_JWT_SECRETS: Record<string, true> = {
  'change-me-to-a-long-random-string': true,
  'eatwise-dev-secret': true,
};

/**
 * 用户 JWT secret：NODE_ENV=production 时必须显式配置 JWT_SECRET（启动 fail-fast），
 * 并拒绝仓库公开占位值与过短 secret（HS256 可被公开密钥伪造任意用户令牌）；
 * 缺省值 'eatwise-dev-secret' 仅供开发/测试使用。
 */
export function resolveJwtSecret(config: ConfigService): string {
  const secret = config.get<string>('JWT_SECRET');
  if (config.get<string>('NODE_ENV') === 'production') {
    if (!secret) {
      throw new Error('JWT_SECRET must be explicitly configured when NODE_ENV=production');
    }
    if (PLACEHOLDER_JWT_SECRETS[secret] || secret.length < 32) {
      throw new Error(
        'JWT_SECRET must be a private random string (>=32 chars, not a repo placeholder) in production',
      );
    }
  }
  return secret ?? 'eatwise-dev-secret';
}

@Module({
  imports: [
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: resolveJwtSecret(config),
        signOptions: { expiresIn: Number(config.get('JWT_ACCESS_TTL_SEC', 7200)) },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, { provide: APP_GUARD, useClass: JwtAuthGuard }],
  exports: [AuthService],
})
export class AuthModule {}

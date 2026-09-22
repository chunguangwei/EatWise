import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AdminAuthService } from '../src/admin/admin-auth.service';
import { resolveJwtSecret } from '../src/auth/auth.module';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';

/** JWT secret 生产 fail-fast：缺省值 'eatwise-dev-secret' 仅限开发/测试 */
describe('JWT secret 生产环境 fail-fast', () => {
  const savedEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...savedEnv };
  });

  function makeAdminAuth(): AdminAuthService {
    return new AdminAuthService(
      new MemoryStoreDriver(new DataStore()),
      {} as JwtService,
      new ConfigService(),
    );
  }

  it('开发/测试（无 NODE_ENV=production）：未配置 JWT_SECRET → 回落缺省值', () => {
    delete process.env.JWT_SECRET;
    process.env.NODE_ENV = 'test';
    expect(resolveJwtSecret(new ConfigService())).toBe('eatwise-dev-secret');
    process.env.NODE_ENV = 'development';
    expect(resolveJwtSecret(new ConfigService())).toBe('eatwise-dev-secret');
  });

  it('生产未显式配置 JWT_SECRET → 抛错（启动 fail-fast）', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.JWT_SECRET;
    expect(() => resolveJwtSecret(new ConfigService())).toThrow(/JWT_SECRET/);
  });

  it('生产显式配置足够长的 JWT_SECRET → 使用配置值', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'x'.repeat(32);
    expect(resolveJwtSecret(new ConfigService())).toBe('x'.repeat(32));
  });

  it('生产用仓库公开占位值 / 过短 secret → 抛错（HS256 可被公开密钥伪造）', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'change-me-to-a-long-random-string';
    expect(() => resolveJwtSecret(new ConfigService())).toThrow(/placeholder/);
    process.env.JWT_SECRET = 'eatwise-dev-secret';
    expect(() => resolveJwtSecret(new ConfigService())).toThrow(/placeholder/);
    process.env.JWT_SECRET = 'short';
    expect(() => resolveJwtSecret(new ConfigService())).toThrow(/32/);
  });

  it('生产未显式配置 ADMIN_JWT_SECRET → 启动钩子抛错（fail-fast）', async () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'x'.repeat(32);
    delete process.env.ADMIN_JWT_SECRET;
    await expect(makeAdminAuth().onApplicationBootstrap()).rejects.toThrow(/ADMIN_JWT_SECRET/);
  });

  it('生产显式配置 ADMIN_JWT_SECRET → 启动正常；开发缺省 → 派生 secret 可用', async () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'prod-secret';
    process.env.ADMIN_JWT_SECRET = 'admin-secret';
    const prod = makeAdminAuth();
    await expect(prod.onApplicationBootstrap()).resolves.toBeUndefined();
    expect(prod.jwtSecret()).toBe('admin-secret');

    process.env.NODE_ENV = 'test';
    delete process.env.JWT_SECRET;
    delete process.env.ADMIN_JWT_SECRET;
    const dev = makeAdminAuth();
    await expect(dev.onApplicationBootstrap()).resolves.toBeUndefined();
    expect(dev.jwtSecret()).toBe('eatwise-dev-secret:admin');
  });
});

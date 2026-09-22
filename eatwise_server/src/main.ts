import { RequestMethod, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { DataStore } from './common/store/data-store';
import { loadFoodSeedFromFile } from './common/store/food-seed-loader';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  // Caddy 反代后 req.ip 恒等于代理 IP：信任一跳 X-Forwarded-For，
  // 否则全局限流（ThrottlerGuard）会把全站用户塞进同一个 300/min 桶。
  app.set('trust proxy', 1);
  // D-16：开发环境把 foods.seed.json 全量库灌入内存 DataStore，
  // prisma 驱动模式下食物库由 `npm run prisma:seed` 灌入 PostgreSQL，此处跳过。
  if ((process.env.STORE_DRIVER ?? 'memory') !== 'prisma') {
    const seed = loadFoodSeedFromFile(app.get(DataStore));
    if (seed && !seed.skipped) {
      // eslint-disable-next-line no-console
      console.log(`Food seed v${seed.version}: ${seed.loaded} foods loaded into DataStore`);
    }
  }
  app.use(helmet());
  // 所有路径以 /v1 为版本前缀（契约 §1.1）；/admin 管理控制台静态页除外
  app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
  // 防腐层：class-validator 全量校验（规格 §5）
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: false,
    }),
  );
  app.enableShutdownHooks();
  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  // eslint-disable-next-line no-console
  console.log(`EatWise server listening on http://localhost:${port}/v1`);
}

void bootstrap();

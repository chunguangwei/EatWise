import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { DataStore } from './common/store/data-store';
import { loadFoodSeedFromFile } from './common/store/food-seed-loader';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // D-16：开发环境把 foods.seed.json 全量库灌入内存 DataStore，
  // 保证 K1/K2 双语搜索有真实数据；文件缺失时静默降级为内置 fixture。
  const seed = loadFoodSeedFromFile(app.get(DataStore));
  if (seed && !seed.skipped) {
    // eslint-disable-next-line no-console
    console.log(`Food seed v${seed.version}: ${seed.loaded} foods loaded into DataStore`);
  }
  app.use(helmet());
  // 所有路径以 /v1 为版本前缀（契约 §1.1）
  app.setGlobalPrefix('v1');
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

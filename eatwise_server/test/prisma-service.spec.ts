import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../src/infra/prisma.service';

function configFor(driver: string): ConfigService {
  const config = new ConfigService();
  const values: Record<string, string> = {
    STORE_DRIVER: driver,
    DATABASE_URL: 'postgresql://localhost/unavailable',
  };
  jest.spyOn(config, 'get').mockImplementation((key: string) => values[key]);
  return config;
}

describe('PrismaService driver lifecycle', () => {
  it('memory driver starts without PostgreSQL even when DATABASE_URL is configured', async () => {
    const service = new PrismaService(configFor('memory'));
    const connect = jest
      .spyOn(service, '$connect')
      .mockRejectedValue(new Error('database offline'));
    await expect(service.onModuleInit()).resolves.toBeUndefined();
    expect(connect).not.toHaveBeenCalled();
  });

  it('prisma driver propagates connection failure at startup', async () => {
    const service = new PrismaService(configFor('prisma'));
    jest.spyOn(service, '$connect').mockRejectedValue(new Error('database offline'));
    await expect(service.onModuleInit()).rejects.toThrow('database offline');
  });
});

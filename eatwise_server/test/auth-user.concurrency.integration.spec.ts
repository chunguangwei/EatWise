import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';
import { AuthService } from '../src/auth/auth.service';
import { DataStore } from '../src/common/store/data-store';
import { PrismaStore } from '../src/common/store/prisma-store';
import { PrismaService } from '../src/infra/prisma.service';
import { UserService } from '../src/user/user.service';

const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;
const describePg = RUN_PG ? describe : describe.skip;

describePg('Auth/User 并发（真实 PostgreSQL，双连接）', () => {
  let prismaA: PrismaService;
  let prismaB: PrismaService;
  let storeA: PrismaStore;
  let storeB: PrismaStore;
  const createdUserIds = new Set<string>();
  const password = 'Passw0rd123';

  const username = () => `it_concurrency_${randomUUID()}`;
  const createAuth = (driver: PrismaStore) =>
    new AuthService(
      new DataStore(),
      driver,
      new JwtService({ secret: 'test-secret', signOptions: { expiresIn: 7200 } }),
      new ConfigService(),
    );

  beforeAll(async () => {
    prismaA = new PrismaService(new ConfigService());
    prismaB = new PrismaService(new ConfigService());
    await Promise.all([prismaA.$connect(), prismaB.$connect()]);
    storeA = new PrismaStore(prismaA);
    storeB = new PrismaStore(prismaB);
  }, 30_000);

  afterAll(async () => {
    if (storeA) {
      for (const userId of createdUserIds) {
        await storeA.purgeUserData(userId).catch(() => undefined);
      }
    }
    await Promise.all([prismaA?.$disconnect(), prismaB?.$disconnect()]);
  }, 30_000);

  it('跨实例并发 refresh 至多一个成功，赢家会话保持有效', async () => {
    const authA = createAuth(storeA);
    const authB = createAuth(storeB);
    const registered = await authA.register(username(), password);
    createdUserIds.add(registered.user.id);

    const results = await Promise.allSettled([
      authA.refresh(registered.refreshToken),
      authB.refresh(registered.refreshToken),
    ]);
    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect((rejected[0] as PromiseRejectedResult).reason).toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });

    const winner = (fulfilled[0] as PromiseFulfilledResult<{ refreshToken: string }>).value;
    const active = await storeA.listActiveRefreshTokens(registered.user.id);
    expect(active).toHaveLength(1);
    await expect(authB.refresh(winner.refreshToken)).resolves.toMatchObject({ isNewUser: false });
  }, 30_000);

  it('跨实例同名注册只有一个成功，其余 AUTH_USERNAME_TAKEN', async () => {
    const name = username();
    const results = await Promise.allSettled([
      createAuth(storeA).register(name, password),
      createAuth(storeB).register(name.toUpperCase(), password),
    ]);
    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');
    for (const result of fulfilled) {
      createdUserIds.add(
        (result as PromiseFulfilledResult<{ user: { id: string } }>).value.user.id,
      );
    }

    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect((rejected[0] as PromiseRejectedResult).reason).toMatchObject({
      code: 'AUTH_USERNAME_TAKEN',
    });
    expect(await prismaA.user.count({ where: { username: name } })).toBe(1);
  }, 30_000);

  it('跨实例并发 settingsPrefs PATCH 各改不同键，最终两键都在', async () => {
    const user = await storeA.createUser({
      username: username(),
      settingsPrefs: { existing: 'kept' },
    });
    createdUserIds.add(user.id);
    const serviceA = new UserService(storeA);
    const serviceB = new UserService(storeB);

    await Promise.all([
      serviceA.patchMe(user.id, { settingsPrefs: { theme: 'dark' } }),
      serviceB.patchMe(user.id, { settingsPrefs: { locale: 'en-US' } }),
    ]);

    const merged = (await storeA.findUserById(user.id))?.settingsPrefs as Record<string, unknown>;
    expect(merged).toMatchObject({ existing: 'kept', theme: 'dark', locale: 'en-US' });
    expect(merged.syncedAt).toEqual(expect.any(String));
  }, 30_000);
});

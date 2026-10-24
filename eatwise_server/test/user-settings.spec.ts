import { DataStore, UserEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { UserService } from '../src/user/user.service';

class SnapshotMemoryStoreDriver extends MemoryStoreDriver {
  override async findUserById(userId: string): Promise<UserEntity | null> {
    const user = await super.findUserById(userId);
    return user ? structuredClone(user) : null;
  }
}

describe('UserService settingsPrefs 并发合并', () => {
  it('两个并发 PATCH 各改不同键，最终两键与既有键都保留且 syncedAt 由服务端打戳', async () => {
    const store = new DataStore();
    const driver = new SnapshotMemoryStoreDriver(store);
    const serviceA = new UserService(driver);
    const serviceB = new UserService(driver);
    const user = store.createUser({
      phone: '+8613900000099',
      settingsPrefs: { existing: 'kept', theme: 'system' },
    });

    await Promise.all([
      serviceA.patchMe(user.id, {
        settingsPrefs: { theme: 'dark', syncedAt: '2026-01-01T00:00:00.000Z' },
      }),
      serviceB.patchMe(user.id, {
        settingsPrefs: { locale: 'en-US', syncedAt: '2026-01-02T00:00:00.000Z' },
      }),
    ]);

    const merged = (await driver.findUserById(user.id))?.settingsPrefs as Record<string, unknown>;
    expect(merged).toMatchObject({ existing: 'kept', theme: 'dark', locale: 'en-US' });
    expect(merged.syncedAt).toEqual(expect.any(String));
    expect(Date.parse(merged.syncedAt as string)).not.toBeNaN();
    expect(merged.syncedAt).not.toBe('2026-01-01T00:00:00.000Z');
    expect(merged.syncedAt).not.toBe('2026-01-02T00:00:00.000Z');
  });
});

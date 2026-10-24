import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe('MemoryStoreDriver.runInTransaction', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
  });

  it('同键 Promise 队列串行，后一个事务读到前一个提交', async () => {
    let active = 0;
    let maxActive = 0;
    const observed: string[] = [];
    await Promise.all(
      ['first', 'second'].map((id) =>
        driver.runInTransaction(['same-key'], async (tx) => {
          active += 1;
          maxActive = Math.max(maxActive, active);
          try {
            observed.push([...store.users.keys()].join(','));
            await delay(15);
            await tx.createUser({ id });
          } finally {
            active -= 1;
          }
        }),
      ),
    );
    expect(maxActive).toBe(1);
    expect(observed).toEqual(['', 'first']);
    expect(store.users.has('first')).toBe(true);
    expect(store.users.has('second')).toBe(true);
  });

  it('不同键可并行，失败事务回滚不清除另一事务提交', async () => {
    let active = 0;
    let maxActive = 0;
    const track = () => {
      active += 1;
      maxActive = Math.max(maxActive, active);
    };
    const failing = driver.runInTransaction(['key-a'], async (tx) => {
      track();
      try {
        await tx.createUser({ id: 'rolled-back' });
        await delay(15);
        throw new Error('force rollback');
      } finally {
        active -= 1;
      }
    });
    const succeeding = driver.runInTransaction(['key-b'], async (tx) => {
      track();
      try {
        await delay(25);
        await tx.createUser({ id: 'committed' });
      } finally {
        active -= 1;
      }
    });
    await expect(failing).rejects.toThrow('force rollback');
    await succeeding;
    expect(maxActive).toBe(2);
    expect(store.users.has('rolled-back')).toBe(false);
    expect(store.users.has('committed')).toBe(true);
  });

  it('嵌套事务不逃回 root，内层异常恢复 savepoint 后外层仍可提交', async () => {
    await driver.runInTransaction(['outer'], async (tx) => {
      await tx.createUser({ id: 'outer-before' });
      await expect(
        tx.runInTransaction(['inner'], async (nested) => {
          await nested.createUser({ id: 'inner-rolled-back' });
          throw new Error('inner failure');
        }),
      ).rejects.toThrow('inner failure');
      await tx.createUser({ id: 'outer-after' });
    });
    expect(store.users.has('outer-before')).toBe(true);
    expect(store.users.has('inner-rolled-back')).toBe(false);
    expect(store.users.has('outer-after')).toBe(true);
  });

  it('不同键并发修改数组型审核队列也按 delta 合并', async () => {
    await Promise.all([
      driver.runInTransaction(['queue-a'], async (tx) => {
        await delay(10);
        await tx.enqueueModerationItem({
          postId: 'post-a',
          source: 'auto',
          reason: 'a',
          createdAt: new Date('2026-01-01T00:00:00.000Z'),
        });
      }),
      driver.runInTransaction(['queue-b'], async (tx) => {
        await delay(20);
        await tx.enqueueModerationItem({
          postId: 'post-b',
          source: 'report',
          reason: 'b',
          createdAt: new Date('2026-01-02T00:00:00.000Z'),
        });
      }),
    ]);
    expect(store.moderationQueue.map((item) => item.postId).sort()).toEqual(['post-a', 'post-b']);
  });
});

import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { PrismaStore } from '../src/common/store/prisma-store';
import { MemoryStoreDriver, StoreDriver } from '../src/common/store/store-driver';
import { PrismaService } from '../src/infra/prisma.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { SocialService } from '../src/social/social.service';
import { StreakService } from '../src/streak/streak.service';

const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;

function barrier() {
  let release!: () => void;
  const reached = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { reached, release };
}

for (const backend of ['memory', 'prisma'] as const) {
  const suite = backend === 'prisma' && !RUN_PG ? describe.skip : describe;
  suite(`社区互动事务 (${backend})`, () => {
    let prisma: PrismaService | undefined;
    let driver: StoreDriver;
    let social: SocialService;
    let author: string;
    let viewer: string;
    const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;

    beforeAll(async () => {
      if (backend === 'prisma') {
        prisma = new PrismaService(new ConfigService());
        await prisma.$connect();
      }
    });
    beforeEach(async () => {
      driver = prisma ? new PrismaStore(prisma) : new MemoryStoreDriver(new DataStore());
      author = (await driver.createUser({ phone: randomUUID(), timezone: 'Asia/Shanghai' })).id;
      viewer = (await driver.createUser({ phone: randomUUID(), timezone: 'Asia/Shanghai' })).id;
      social = new SocialService(driver, new StreakService(driver), new StubModerationService());
    });
    afterEach(async () => {
      jest.restoreAllMocks();
      await driver.purgeUserData(author);
      await driver.purgeUserData(viewer);
    });
    afterAll(async () => {
      await prisma?.$disconnect();
    });

    async function createPost() {
      return (await social.create(author, {
        clientRequestId: randomUUID(),
        text: '互动事务回归',
      })) as { id: string };
    }

    async function queueFor(id: string) {
      return (await driver.listModerationQueue()).filter((item) => item.postId === id);
    }

    // 在首个操作读完旧快照后暂停；第二个操作要么等待同一把锁，要么真的完成。
    // 以这两个确定事件释放首操作，不依赖 sleep，也不会让正确实现死锁。
    async function contend(first: () => Promise<unknown>, second: () => Promise<unknown>) {
      const snapshotRead = barrier();
      const resumeFirst = barrier();
      const read = prototype.findPostById;
      const pausedRead = jest
        .spyOn(prototype, 'findPostById')
        .mockImplementationOnce(async function (this: StoreDriver, id: string) {
          const post = await read.call(this, id);
          snapshotRead.release();
          await resumeFirst.reached;
          return post;
        });
      const firstResult = first();
      await snapshotRead.reached;
      const lockAttempt = barrier();
      const run = driver.runInTransaction.bind(driver);
      const transaction = jest
        .spyOn(driver, 'runInTransaction')
        .mockImplementation((keys, work) => {
          const result = run(keys, work);
          lockAttempt.release();
          return result;
        });
      const secondResult = second().then(
        (value) => ({ status: 'fulfilled' as const, value }),
        (reason: unknown) => ({ status: 'rejected' as const, reason }),
      );
      try {
        await Promise.race([lockAttempt.reached, secondResult]);
      } finally {
        resumeFirst.release();
      }
      await firstResult;
      const result = await secondResult;
      pausedRead.mockRestore();
      transaction.mockRestore();
      return result;
    }

    for (const stage of [
      'incrementPostReportCount',
      'savePost',
      'enqueueModerationItem',
    ] as const) {
      it(`举报在 ${stage} 失败时完整回滚，重试仍能正确下架入队`, async () => {
        const post = await createPost();
        const failure = jest
          .spyOn(prototype, stage)
          .mockRejectedValueOnce(new Error('report failed'));
        await expect(social.report(viewer, post.id, 'spam')).rejects.toThrow('report failed');
        expect(await driver.hasPostReport(post.id, viewer)).toBe(false);
        expect(await driver.findPostById(post.id)).toMatchObject({
          auditStatus: 'approved',
          reportCount: 0,
          reportedAt: null,
          version: 1,
        });
        expect(await queueFor(post.id)).toHaveLength(0);
        failure.mockRestore();
        await expect(social.report(viewer, post.id, 'spam')).resolves.toEqual({ reported: true });
        expect(await driver.findPostById(post.id)).toMatchObject({
          auditStatus: 'rejected',
          reportCount: 1,
        });
        expect(await queueFor(post.id)).toHaveLength(1);
      });
    }

    it('同用户并发举报只计数一次、只入队一次，重放返回成功', async () => {
      const post = await createPost();
      const results = await Promise.all([
        social.report(viewer, post.id, 'spam'),
        social.report(viewer, post.id, 'spam'),
        social.report(viewer, post.id, 'spam'),
      ]);
      expect(results).toEqual([{ reported: true }, { reported: true }, { reported: true }]);
      expect(await driver.findPostById(post.id)).toMatchObject({ reportCount: 1 });
      expect(await queueFor(post.id)).toHaveLength(1);
      await expect(social.report(viewer, post.id)).resolves.toEqual({ reported: true });
    });

    it('举报读完更新快照后发生作者删除，不得以旧快照复活帖子或重建审核队列', async () => {
      const post = await createPost();
      const snapshotRead = barrier();
      const resumeReport = barrier();
      const reportLock = barrier();
      let reporting = true;
      let reads = 0;
      const run = driver.runInTransaction.bind(driver);
      jest.spyOn(driver, 'runInTransaction').mockImplementation((keys, work) => {
        if (reporting && keys.includes(`post:${post.id}`)) reportLock.release();
        return run(keys, work);
      });
      const read = prototype.findPostById;
      jest.spyOn(prototype, 'findPostById').mockImplementation(async function (
        this: StoreDriver,
        id: string,
      ) {
        const result = await read.call(this, id);
        if (id === post.id && ++reads === 2) {
          snapshotRead.release();
          await resumeReport.reached;
        }
        return result;
      });
      const report = social.report(viewer, post.id, 'spam');
      await snapshotRead.reached;
      reporting = false;
      const deletion = social.remove(author, post.id);
      try {
        // 有共享锁时删除会排在举报后；没有锁时让删除先完成，稳定复现旧快照复活。
        await Promise.race([reportLock.reached, deletion]);
      } finally {
        resumeReport.release();
      }
      await Promise.all([report, deletion]);
      expect((await driver.findPostById(post.id))?.deletedAt).not.toBeNull();
      expect(await queueFor(post.id)).toHaveLength(0);
      await expect(social.getById(author, post.id)).rejects.toMatchObject({ status: 404 });
    });

    it.each(['like', 'unlike'] as const)(
      '人工审核持有旧快照时 %s 不丢计数或版本',
      async (action) => {
        const post = await createPost();
        if (action === 'unlike') await social.like(author, post.id);
        const initial = await driver.findPostById(post.id);
        const result = await contend(
          () => social.adminReview(post.id, { action: 'reject' }),
          () => social[action](author, post.id),
        );
        expect(result.status).toBe('fulfilled');
        expect(await driver.findPostById(post.id)).toMatchObject({
          auditStatus: 'rejected',
          likeCount: action === 'like' ? 1 : 0,
          version: initial!.version + 2,
        });
        expect(await driver.hasPostLike(post.id, author)).toBe(action === 'like');
      },
    );

    it.each(['report', 'like', 'unlike'] as const)(
      '作者删除持锁后到达的 %s 必须看见已删除状态',
      async (action) => {
        const post = await createPost();
        const result = await contend(
          () => social.remove(author, post.id),
          () => social[action](viewer, post.id),
        );
        expect(result).toMatchObject({ status: 'rejected', reason: { status: 410 } });
        expect((await driver.findPostById(post.id))?.deletedAt).not.toBeNull();
        expect(await driver.hasPostReport(post.id, viewer)).toBe(false);
        expect(await driver.hasPostLike(post.id, viewer)).toBe(false);
        expect(await queueFor(post.id)).toHaveLength(0);
      },
    );

    it('重复和并发点赞幂等，取消点赞也只减一次', async () => {
      const post = await createPost();
      await Promise.all([social.like(viewer, post.id), social.like(viewer, post.id)]);
      await expect(social.like(viewer, post.id)).resolves.toMatchObject({ likeCount: 1 });
      await Promise.all([social.unlike(viewer, post.id), social.unlike(viewer, post.id)]);
      expect(await driver.findPostById(post.id)).toMatchObject({ likeCount: 0, version: 3 });
      expect(await driver.hasPostLike(post.id, viewer)).toBe(false);
    });

    it.each(['report', 'like', 'unlike'] as const)(
      '%s 在事务内完成权限及互动读取，不逃回根 driver',
      async (action) => {
        const post = await createPost();
        const guards = (
          ['findPostById', 'hasUserBlock', 'hasPostLike', 'hasPostReport'] as const
        ).map((method) =>
          jest.spyOn(driver, method).mockRejectedValue(new Error('root driver escaped')),
        );
        try {
          await expect(social[action](viewer, post.id)).resolves.toBeDefined();
        } finally {
          for (const guard of guards) guard.mockRestore();
        }
      },
    );
  });
}

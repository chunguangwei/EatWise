import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { PrismaStore } from '../src/common/store/prisma-store';
import { MemoryStoreDriver, StoreDriver } from '../src/common/store/store-driver';
import { PrismaService } from '../src/infra/prisma.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { CreatePostDto } from '../src/social/social.dto';
import { SocialService } from '../src/social/social.service';
import { StreakService } from '../src/streak/streak.service';

const RUN_PG = process.env.RUN_PG_TESTS === '1' && !!process.env.DATABASE_URL;

for (const backend of ['memory', 'prisma'] as const) {
  const suite = backend === 'prisma' && !RUN_PG ? describe.skip : describe;
  suite(`图片帖人工审核 (${backend})`, () => {
    let prisma: PrismaService | undefined;
    let driver: StoreDriver;
    let social: SocialService;
    let author: string;
    let viewer: string;

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

    function imagePost(): CreatePostDto {
      return {
        clientRequestId: randomUUID(),
        text: '今天的午餐',
        imageUrls: [`/v1/uploads/${randomUUID()}.jpg`],
      };
    }

    async function create(dto = imagePost()) {
      return (await social.create(author, dto)) as {
        id: string;
        auditStatus: string;
        auditReason: { zh: string; en: string } | null;
      };
    }

    async function queueFor(id: string) {
      return (await driver.listModerationQueue()).filter((item) => item.postId === id);
    }

    async function ownPosts() {
      return (await driver.listPostsForAdmin(undefined)).filter((post) => post.userId === author);
    }

    it('图片帖仅作者可见，进入 pending 队列且其他用户无法互动', async () => {
      const post = await create();
      expect(post.auditStatus).toBe('pending');
      expect(post.auditReason?.zh).toBeTruthy();
      expect(post.auditReason?.en).toBeTruthy();
      expect((await social.feed(author)).items.map((item) => item.id)).toContain(post.id);
      expect((await social.feed(viewer)).items.map((item) => item.id)).not.toContain(post.id);
      await expect(social.getById(viewer, post.id)).rejects.toMatchObject({ status: 404 });
      await expect(social.like(viewer, post.id)).rejects.toMatchObject({ status: 404 });
      await expect(social.report(viewer, post.id)).rejects.toMatchObject({ status: 404 });
      expect((await social.adminList('pending')).items.map((item) => item.id)).toContain(post.id);
      expect(await queueFor(post.id)).toMatchObject([{ source: 'auto' }]);
    });

    it.each([undefined, []])('纯文字帖（imageUrls=%j）保持直接发布', async (imageUrls) => {
      const post = await create({ ...imagePost(), imageUrls });
      expect(post.auditStatus).toBe('approved');
      expect((await social.feed(viewer)).items.map((item) => item.id)).toContain(post.id);
      expect(await queueFor(post.id)).toHaveLength(0);
    });

    it('人工通过后公开可见并从待审队列移除', async () => {
      const post = await create();
      const reviewed = await social.adminReview(post.id, { action: 'approve' });
      expect(reviewed).toMatchObject({ auditStatus: 'approved', version: 2, auditReason: null });
      expect((await social.getById(viewer, post.id)).id).toBe(post.id);
      expect((await social.feed(viewer)).items.map((item) => item.id)).toContain(post.id);
      expect(await queueFor(post.id)).toHaveLength(0);
    });

    it('人工拒绝后仅作者能查看原因，待审队列清理', async () => {
      const post = await create();
      await social.adminReview(post.id, { action: 'reject', reason: '请重新上传清晰图片' });
      expect(await social.getById(author, post.id)).toMatchObject({
        auditStatus: 'rejected',
        auditReason: { zh: '请重新上传清晰图片' },
      });
      await expect(social.getById(viewer, post.id)).rejects.toMatchObject({ status: 404 });
      expect(await queueFor(post.id)).toHaveLength(0);
    });

    it('同幂等键并发创建只生成一个帖子和一个待审项', async () => {
      const dto = imagePost();
      const results = await Promise.all([create(dto), create(dto), create(dto)]);
      expect(new Set(results.map((post) => post.id)).size).toBe(1);
      expect(await ownPosts()).toHaveLength(1);
      expect(await queueFor(results[0].id)).toHaveLength(1);
      await expect(create({ ...dto, text: '不同内容' })).rejects.toMatchObject({ status: 409 });
      expect(await ownPosts()).toHaveLength(1);
    });

    for (const method of ['enqueueModerationItem', 'saveIdempotencyRecord'] as const) {
      it(`${method} 写入失败时回滚帖子；原请求重试只有一条记录`, async () => {
        const dto = imagePost();
        const prototype =
          backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
        const failure = jest
          .spyOn(prototype, method)
          .mockRejectedValueOnce(new Error('write failed'));
        await expect(create(dto)).rejects.toThrow('write failed');
        expect(await ownPosts()).toHaveLength(0);
        expect(await driver.findIdempotencyRecord(author, 'posts', dto.clientRequestId)).toBeNull();
        failure.mockRestore();
        const post = await create(dto);
        expect(await ownPosts()).toHaveLength(1);
        expect(await queueFor(post.id)).toHaveLength(1);
      });
    }

    it('审核清队列失败时帖子仍待审且重试可完成', async () => {
      const post = await create();
      const prototype = backend === 'memory' ? MemoryStoreDriver.prototype : PrismaStore.prototype;
      const failure = jest
        .spyOn(prototype, 'removeModerationByPost')
        .mockRejectedValueOnce(new Error('queue removal failed'));
      await expect(social.adminReview(post.id, { action: 'approve' })).rejects.toThrow(
        'queue removal failed',
      );
      expect(await driver.findPostById(post.id)).toMatchObject({
        auditStatus: 'pending',
        version: 1,
      });
      expect(await queueFor(post.id)).toHaveLength(1);
      failure.mockRestore();
      await social.adminReview(post.id, { action: 'approve' });
      expect(await queueFor(post.id)).toHaveLength(0);
    });

    it('作者删除待审图片帖时移除审核队列，后续审核不能恢复它', async () => {
      const post = await create();
      await social.remove(author, post.id);
      expect(await queueFor(post.id)).toHaveLength(0);
      expect((await social.adminList('pending')).items.map((item) => item.id)).not.toContain(
        post.id,
      );
      await expect(social.adminReview(post.id, { action: 'approve' })).rejects.toMatchObject({
        status: 410,
      });
    });

    it('并发重复审核只落一次决定，版本只增加一次', async () => {
      const post = await create();
      const results = await Promise.allSettled([
        social.adminReview(post.id, { action: 'approve' }),
        social.adminReview(post.id, { action: 'approve' }),
      ]);
      expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
      expect(await driver.findPostById(post.id)).toMatchObject({
        auditStatus: 'approved',
        version: 2,
      });
      expect(await queueFor(post.id)).toHaveLength(0);
    });
  });
}

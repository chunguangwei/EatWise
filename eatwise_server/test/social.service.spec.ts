import { randomUUID } from 'crypto';
import { DataStore, PostEntity } from '../src/common/store/data-store';
import { newId } from '../src/common/utils/id.util';
import { addDays, localDateOf } from '../src/common/utils/time.util';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { SocialService } from '../src/social/social.service';
import { StreakService } from '../src/streak/streak.service';
import { FastingRecordEntity } from '../src/common/store/data-store';

const TZ = 'Asia/Shanghai';

describe('社区打卡（M5 P1 / D-17 先审后发）', () => {
  let store: DataStore;
  let social: SocialService;
  let userId: string;
  let otherId: string;

  beforeEach(() => {
    store = new DataStore();
    social = new SocialService(store, new StreakService(store), new StubModerationService());
    userId = store.createUser({ phone: '+8613800138000', timezone: TZ, nickname: '小林' }).id;
    otherId = store.createUser({ phone: '+8613800138001', timezone: TZ }).id;
  });

  function addQualifiedRecord(uid: string, date: string) {
    const now = new Date();
    const record: FastingRecordEntity = {
      id: newId(),
      userId: uid,
      attributionDate: date,
      plannedStartAt: now,
      plannedEndAt: now,
      actualStartAt: now,
      actualEndAt: now,
      extendedMinutes: 0,
      fastedMinutes: 960,
      result: 'completed',
      isQualified: true,
      eventLog: [],
      clientRequestId: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
    };
    store.fastingRecords.set(record.id, record);
  }

  function createPost(uid: string, text: string) {
    return social.create(uid, { clientRequestId: randomUUID(), text }) as Promise<{
      id: string;
      auditStatus: string;
      streakDaysAtPost: number | null;
    }>;
  }

  it('机审通过 → approved 上流，自动附带当前 streak 天数（服务端权威）', async () => {
    const today = localDateOf(new Date(), TZ);
    addQualifiedRecord(userId, addDays(today, -1));
    const post = await createPost(userId, '第 2 天，感觉不错！');
    expect(post.auditStatus).toBe('approved');
    expect(post.streakDaysAtPost).toBe(1); // 昨天达标、今天未达标 → currentStreak=1
  });

  it('命中违规词 → 400 POST_CONTENT_REJECTED（双语 reason），不入库不上流', async () => {
    await expect(createPost(userId, '来赌博网站看看')).rejects.toThrow(
      expect.objectContaining({ code: 'POST_CONTENT_REJECTED' }) as unknown as Error,
    );
    expect(store.posts.size).toBe(0);
  });

  it('命中疑似词 → pending 转人工队列，他人不可见、本人可见', async () => {
    const post = await createPost(userId, '打卡顺便做个兼职推广');
    expect(post.auditStatus).toBe('pending');
    expect(store.moderationQueue.some((q) => q.postId === post.id && q.source === 'auto')).toBe(
      true,
    );
    // 他人的流里不可见
    const otherFeed = social.feed(otherId);
    expect(otherFeed.items.find((i: { id: string }) => i.id === post.id)).toBeUndefined();
    // 本人的流里可见（带审核中标记）
    const ownFeed = social.feed(userId);
    expect(ownFeed.items.find((i: { id: string }) => i.id === post.id)).toBeTruthy();
    // 他人详情 404
    expect(() => social.getById(otherId, post.id)).toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('发布幂等：同 clientRequestId 重放返回首次结果，不重复发帖', async () => {
    const clientRequestId = randomUUID();
    const first = (await social.create(userId, { clientRequestId, text: '第一天打卡' })) as {
      id: string;
    };
    const replay = (await social.create(userId, { clientRequestId, text: '第一天打卡' })) as {
      id: string;
    };
    expect(replay.id).toBe(first.id);
    expect(store.posts.size).toBe(1);
  });

  it('发布幂等：同键不同体 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const clientRequestId = randomUUID();
    await social.create(userId, { clientRequestId, text: '第一天打卡' });
    await expect(social.create(userId, { clientRequestId, text: '改过的内容' })).rejects.toThrow(
      expect.objectContaining({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' }) as unknown as Error,
    );
  });

  it('打卡流：混排倒序（不分语言圈 D-15），他人的 rejected 不可见', async () => {
    const a = (await createPost(userId, 'Day 1 in English')) as { id: string };
    const b = (await createPost(otherId, '中文打卡第二天')) as { id: string };
    // 直接篡改一帖为 rejected（模拟人工复核拒绝），验证过滤
    const c = (await createPost(otherId, '第三天')) as { id: string };
    store.posts.get(c.id)!.auditStatus = 'rejected';
    // 显式时间戳保证可预期的倒序（同毫秒下由 id 决胜，UUID 不可预期）
    store.posts.get(a.id)!.createdAt = new Date(2026, 6, 28, 10, 0, 0);
    store.posts.get(b.id)!.createdAt = new Date(2026, 6, 28, 11, 0, 0);

    const feed = social.feed(userId);
    const ids = feed.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(a.id);
    expect(ids).toContain(b.id);
    expect(ids).not.toContain(c.id);
    expect(ids.indexOf(b.id)).toBeLessThan(ids.indexOf(a.id)); // 倒序：后发在前
  });

  it('游标分页：逐页取完不重复不遗漏，非法游标 400', async () => {
    for (let i = 0; i < 25; i++) {
      const post = (await createPost(userId, `打卡 ${i}`)) as { id: string };
      // 保证 createdAt 严格递增（同毫秒下分页靠 id 次序，这里强制可预期顺序）
      store.posts.get(post.id)!.createdAt = new Date(2026, 6, 28, 10, 0, i);
    }
    const seen: string[] = [];
    let cursor: string | undefined;
    do {
      const page: {
        items: Array<{ id: string }>;
        pageInfo: { nextCursor: string | null; hasMore: boolean };
      } = social.feed(userId, 10, cursor);
      seen.push(...page.items.map((i) => i.id));
      cursor = page.pageInfo.nextCursor ?? undefined;
      if (!page.pageInfo.hasMore) break;
    } while (cursor);
    expect(seen.length).toBe(25);
    expect(new Set(seen).size).toBe(25);
    expect(() => social.feed(userId, 10, 'not-a-cursor')).toThrow(
      expect.objectContaining({ code: 'INVALID_CURSOR' }) as unknown as Error,
    );
  });

  it('点赞幂等：重复点赞不重复计数；取消点赞幂等', async () => {
    const post = (await createPost(userId, '求点赞')) as { id: string };
    const l1 = social.like(otherId, post.id);
    const l2 = social.like(otherId, post.id);
    const l3 = social.like(userId, post.id);
    expect(l1.likeCount).toBe(1);
    expect(l2.likeCount).toBe(1);
    expect(l3.likeCount).toBe(2);
    // 视图侧 likedByMe 跟随用户
    const viewForOther = social.getById(otherId, post.id) as { likedByMe: boolean };
    expect(viewForOther.likedByMe).toBe(true);

    const u1 = social.unlike(otherId, post.id);
    const u2 = social.unlike(otherId, post.id);
    expect(u1.likeCount).toBe(1);
    expect(u2.likeCount).toBe(1);
    expect(u2.likedByMe).toBe(false);
  });

  it('已删除帖子点赞 → 410 RESOURCE_GONE；删除幂等', async () => {
    const post = (await createPost(userId, '马上删掉')) as { id: string };
    social.remove(userId, post.id);
    expect(() => social.like(otherId, post.id)).toThrow(
      expect.objectContaining({ code: 'RESOURCE_GONE' }) as unknown as Error,
    );
    // 已删除 → 打卡流不出现；他人点赞 410；重复删除 200
    expect(social.feed(otherId).items.length).toBe(0);
    expect(social.remove(userId, post.id)).toEqual({ deleted: true });
    // 他人删除 → 404
    const post2 = (await createPost(userId, '别人的')) as { id: string };
    expect(() => social.remove(otherId, post2.id)).toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('举报：记录并下架（他人即刻不可见）→ 转人工队列；同用户同帖幂等', async () => {
    const post = (await createPost(userId, '被举报的帖子')) as { id: string };
    social.report(otherId, post.id, '广告');
    const entity = store.posts.get(post.id) as PostEntity;
    expect(entity.auditStatus).toBe('rejected');
    expect(entity.auditReason?.zh).toContain('下架');
    expect(store.moderationQueue.some((q) => q.postId === post.id && q.source === 'report')).toBe(
      true,
    );
    // 下架后他人 feed 不可见
    expect(social.feed(otherId).items.length).toBe(0);
    // 重复举报不重复入队
    const queueLen = store.moderationQueue.length;
    social.report(otherId, post.id, '广告');
    expect(store.moderationQueue.length).toBe(queueLen);
  });

  it('rejected 帖详情仅作者可见且带双语 auditReason', async () => {
    const post = (await createPost(userId, '正常内容')) as { id: string };
    social.report(otherId, post.id);
    const own = social.getById(userId, post.id) as {
      auditStatus: string;
      auditReason: { zh: string; en: string } | null;
    };
    expect(own.auditStatus).toBe('rejected');
    expect(own.auditReason?.zh).toBeTruthy();
    expect(own.auditReason?.en).toBeTruthy();
    expect(() => social.getById(otherId, post.id)).toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });
});

import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { SocialService } from '../src/social/social.service';
import { StreakService } from '../src/streak/streak.service';
import { UserService } from '../src/user/user.service';

/** UGC 屏蔽用户（App Store 条例 1.2）：屏蔽/解除幂等 + 信息流过滤 + 互动双向拦截 */
describe('UGC 屏蔽用户（user_blocks）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let users: UserService;
  let social: SocialService;
  let meId: string;
  let otherId: string;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    users = new UserService(driver);
    social = new SocialService(driver, new StreakService(driver), new StubModerationService());
    meId = store.createUser({ phone: '+8613900139000', nickname: '我' }).id;
    otherId = store.createUser({ phone: '+8613900139001', nickname: '对方' }).id;
  });

  async function createPost(uid: string, text: string): Promise<{ id: string }> {
    return (await social.create(uid, { clientRequestId: randomUUID(), text })) as {
      id: string;
    };
  }

  it('屏蔽：成功返回 blocked=true；重复屏蔽幂等；不能屏蔽自己 400；屏蔽不存在用户 404', async () => {
    const res = await users.blockUser(meId, otherId);
    expect(res).toEqual({ blocked: true, blockedUserId: otherId });
    expect(store.userBlocks.size).toBe(1);

    await users.blockUser(meId, otherId); // 幂等
    expect(store.userBlocks.size).toBe(1);

    await expect(users.blockUser(meId, meId)).rejects.toThrow(
      expect.objectContaining({ code: 'VALIDATION_ERROR' }) as unknown as Error,
    );
    await expect(users.blockUser(meId, 'no-such-user')).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('解除屏蔽幂等；列表带昵称', async () => {
    await users.blockUser(meId, otherId);
    const list = await users.listBlockedUsers(meId);
    expect(list.items).toEqual([{ userId: otherId, nickname: '对方' }]);

    await users.unblockUser(meId, otherId);
    expect((await users.listBlockedUsers(meId)).items).toEqual([]);
    await users.unblockUser(meId, otherId); // 无记录幂等
    expect(store.userBlocks.size).toBe(0);
  });

  it('信息流过滤：我屏蔽的作者不出现在我的信息流；解除后恢复', async () => {
    const mine = await createPost(meId, '我自己的打卡');
    const theirs = await createPost(otherId, '对方的打卡');

    let feed = await social.feed(meId);
    expect(feed.items.map((i: { id: string }) => i.id)).toEqual(
      expect.arrayContaining([mine.id, theirs.id]),
    );

    await users.blockUser(meId, otherId);
    feed = await social.feed(meId);
    const ids = feed.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(mine.id);
    expect(ids).not.toContain(theirs.id);

    // 单向：对方的流不受我屏蔽影响
    const otherFeed = await social.feed(otherId);
    expect(otherFeed.items.map((i: { id: string }) => i.id)).toContain(mine.id);

    await users.unblockUser(meId, otherId);
    feed = await social.feed(meId);
    expect(feed.items.map((i: { id: string }) => i.id)).toContain(theirs.id);
  });

  it('帖详情：屏蔽后对方帖 404（双向任一方屏蔽均拦截）', async () => {
    const post = await createPost(otherId, '对方的打卡');
    await social.getById(meId, post.id); // 屏蔽前可见

    await users.blockUser(meId, otherId);
    await expect(social.getById(meId, post.id)).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('互动拦截：我屏蔽作者后不能点赞其帖；对方屏蔽我后我也不能点赞其帖', async () => {
    const post = await createPost(otherId, '对方的打卡');
    await social.like(meId, post.id); // 屏蔽前可点赞

    await users.unblockUser(meId, otherId);
    await users.blockUser(meId, otherId);
    await expect(social.like(meId, post.id)).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
    await expect(social.report(meId, post.id, 'spam')).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );

    // 反向：对方屏蔽我 → 我同样不能互动其帖
    await users.unblockUser(meId, otherId);
    await users.blockUser(otherId, meId);
    await expect(social.like(meId, post.id)).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
    // 对方也不能给我发的帖点赞
    const mine = await createPost(meId, '我的打卡');
    await expect(social.like(otherId, mine.id)).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('purgeUserData：账号删除双向清除屏蔽关系（我屏蔽的 + 屏蔽我的）', async () => {
    const thirdId = store.createUser({ phone: '+8613900139002' }).id;
    await users.blockUser(meId, otherId);
    await users.blockUser(thirdId, meId);
    await users.blockUser(otherId, thirdId);
    expect(store.userBlocks.size).toBe(3);

    await driver.purgeUserData(meId);
    expect(store.userBlocks.size).toBe(1); // 只剩 otherId→thirdId
    const [remaining] = [...store.userBlocks.values()];
    expect(remaining.userId).toBe(otherId);
    expect(remaining.blockedUserId).toBe(thirdId);
  });
});

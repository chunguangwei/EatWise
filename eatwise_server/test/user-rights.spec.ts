import { DataStore, FastingRecordEntity, PostEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { maskPhone } from '../src/common/utils/phone.util';
import { UserService } from '../src/user/user.service';

/** U3 导出 / U5 删除冷静期 / U6 撤销 / 到期执行 / U1 手机号脱敏（memory 驱动） */
describe('用户权利（U1/U3/U5/U6，合规 §4.2/§4.3）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let users: UserService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    users = new UserService(driver);
    userId = store.createUser({ phone: '+8613800138000', nickname: '林悦' }).id;
  });

  function seedUserData() {
    const food = [...store.foods.values()][0];
    const now = new Date();
    store.foodEntries.set('e1', {
      id: 'e1',
      userId,
      clientRequestId: 'cr-1',
      eatenAt: now,
      foodId: food.id,
      grams: 100,
      inputMethod: 'manual',
      photoUrl: null,
      nutritionSnapshot: { kcal: 144, proteinG: 13.3, carbsG: 2.8, fatG: 8.8 },
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    });
    const record: FastingRecordEntity = {
      id: 'r1',
      userId,
      attributionDate: '2026-07-29',
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
    store.streaks.set(userId, {
      id: 's1',
      userId,
      currentStreak: 3,
      longestStreak: 7,
      lastQualifiedDate: '2026-07-29',
      milestones: { '3': now.toISOString() },
      makeupCards: { stock: 2, month: '2026-07', usedDates: [] },
      version: 1,
      updatedAt: now,
    });
    const post: PostEntity = {
      id: 'p1',
      userId,
      clientRequestId: null,
      text: '第 3 天打卡',
      imageUrls: ['https://img.example.com/p1.jpg'],
      streakDaysAtPost: 3,
      likeCount: 0,
      auditStatus: 'approved',
      auditReason: null,
      reportCount: 0,
      reportedAt: null,
      visibility: 'public',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    store.posts.set(post.id, post);
  }

  describe('U1 手机号脱敏', () => {
    it('E.164 中国手机号 → 138****8000', () => {
      expect(maskPhone('+8613800138000')).toBe('138****8000');
      expect(maskPhone('13800138000')).toBe('138****8000');
    });

    it('其他号码保底前 3 + **** + 后 4；null/短号安全处理', () => {
      expect(maskPhone('+1415555267')).toBe('141****5267');
      expect(maskPhone('12345')).toBe('****');
      expect(maskPhone(null)).toBeNull();
    });

    it('GET users/me 视图含脱敏手机号，不含明文', async () => {
      const { user } = await users.getMe(userId);
      expect(user.phone).toBe('138****8000');
      expect(JSON.stringify(user)).not.toContain('13800138000');
    });
  });

  describe('U3 数据导出', () => {
    it('聚合 Profile/FoodEntry/FastingRecord/Streak/Post 全量数据', async () => {
      seedUserData();
      const bundle = await users.exportMe(userId);
      expect(bundle.profile.id).toBe(userId);
      expect(bundle.profile.phone).toBe('+8613800138000'); // 本人导出包含明文（PIPL §44/45）
      expect(bundle.foodEntries).toHaveLength(1);
      expect(bundle.fastingRecords).toHaveLength(1);
      expect(bundle.streak?.currentStreak).toBe(3);
      expect(bundle.posts).toHaveLength(1);
      expect(bundle.generatedAt).toMatch(/Z$/);
    });

    it('软删 tombstone 不进导出包；不存在的用户 → NOT_FOUND', async () => {
      seedUserData();
      store.foodEntries.get('e1')!.deletedAt = new Date();
      const bundle = await users.exportMe(userId);
      expect(bundle.foodEntries).toHaveLength(0);
      await expect(users.exportMe('no-such-user')).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });
  });

  describe('U5 删除冷静期', () => {
    it('申请 → deletionStatus=pending + scheduledDeletionAt=7 天后 + 吊销全部会话', async () => {
      store.refreshTokens.set('hash1', {
        id: 't1',
        userId,
        tokenHash: 'hash1',
        deviceId: null,
        expiresAt: new Date(Date.now() + 100000),
        revokedAt: null,
        replacedBy: null,
        createdAt: new Date(),
      });
      const before = Date.now();
      const res = await users.requestDeletion(userId);
      expect(res.deletionStatus).toBe('pending');
      expect(res.coolingOffDays).toBe(7);
      const at = new Date(res.scheduledDeletionAt!).getTime();
      expect(at).toBeGreaterThan(before + 6 * 24 * 3600 * 1000);
      expect(at).toBeLessThanOrEqual(Date.now() + 7 * 24 * 3600 * 1000 + 1000);
      expect(store.refreshTokens.get('hash1')!.revokedAt).not.toBeNull(); // 立即登出所有会话
    });

    it('重复申请幂等：返回在途任务，scheduledDeletionAt 不后移', async () => {
      const first = await users.requestDeletion(userId);
      const second = await users.requestDeletion(userId);
      expect(second.deletionStatus).toBe('pending');
      expect(second.scheduledDeletionAt).toBe(first.scheduledDeletionAt);
    });

    it('U6 冷静期内撤销；重复撤销幂等', async () => {
      await users.requestDeletion(userId);
      const cancelled = await users.cancelDeletion(userId);
      expect(cancelled.deletionStatus).toBeNull();
      expect(cancelled.scheduledDeletionAt).toBeNull();
      const again = await users.cancelDeletion(userId);
      expect(again.deletionStatus).toBeNull();
    });

    it('到期执行：个人数据物理删除 + 打卡帖匿名化；未到期不执行', async () => {
      seedUserData();
      await users.requestDeletion(userId);

      // 未到期：扫描不清除
      expect(await users.executeDueDeletions(new Date())).toEqual([]);
      expect(store.users.get(userId)).toBeTruthy();

      // 快进到冷静期满
      const user = store.users.get(userId)!;
      user.scheduledDeletionAt = new Date(Date.now() - 1000);
      const purged = await users.executeDueDeletions(new Date());
      expect(purged).toEqual([userId]);
      expect(store.users.get(userId)).toBeUndefined(); // 物理删除
      expect(store.foodEntries.size).toBe(0);
      expect(store.fastingRecords.size).toBe(0);
      expect(store.streaks.get(userId)).toBeUndefined();
      const post = store.posts.get('p1')!;
      expect(post.deletedAt).not.toBeNull(); // UGC 匿名化 tombstone
      expect(post.text).toBe('');
      expect(post.imageUrls).toEqual([]);
    });

    it('到期执行：个人自定义食物与贡献候选一并清除；已晋升共享的食物留存', async () => {
      const now = new Date();
      store.customFoods.set('cf_1', {
        id: 'cf_1',
        userId,
        clientRequestId: 'cr-cf-1',
        nameZh: '私房菜',
        nameEn: 'homemade',
        aliases: [],
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        source: 'manual',
        createdAt: now,
      });
      store.foodCandidates.set('fc_1', {
        id: 'fc_1',
        foodId: 'cf_1',
        userId,
        status: 'pending',
        reason: null,
        clientRequestId: 'cr-fc-1',
        version: 1,
        createdAt: now,
        updatedAt: now,
      });
      // 已晋升共享的食物（isCustom=false，createdByUserId 保留溯源）不清除
      const sharedFood = [...store.foods.values()][0];
      store.foods.set(sharedFood.id, { ...sharedFood, createdByUserId: userId });

      await users.requestDeletion(userId);
      store.users.get(userId)!.scheduledDeletionAt = new Date(Date.now() - 1000);
      await users.executeDueDeletions(new Date());

      expect(store.customFoods.size).toBe(0);
      expect(store.foodCandidates.size).toBe(0);
      expect(store.foods.get(sharedFood.id)).toBeTruthy(); // 共享食物留存
    });
  });
});

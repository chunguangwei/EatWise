import { randomUUID } from 'crypto';
import { AdminUsersService } from '../src/admin/admin-users.service';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { PatchUserDto } from '../src/user/user.dto';
import { UserService } from '../src/user/user.service';

/**
 * 用户角色体系（user/admin）：
 * - 注册默认 user；role 不在 PATCHABLE（本人不可自助提权）；
 * - 管理台 setUserRole 设置角色（双驱动同口径，幂等）；
 * - userView 带 role（客户端审批中心入口门控数据源）；
 * - 审核留痕 reviewedBy（管理端管理员 id / 移动端审批用户 id）。
 */
describe('用户角色与审核留痕', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let users: UserService;
  let adminUsers: AdminUsersService;
  let food: FoodService;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    users = new UserService(driver);
    adminUsers = new AdminUsersService(driver);
    food = new FoodService(driver, new StubModerationService());
  });

  it('注册默认 role=user；userView 带 role', async () => {
    const user = store.createUser({ phone: '+8613800138000' });
    expect(user.role).toBe('user');
    const me = (await users.getMe(user.id)) as { user: { role: string } };
    expect(me.user.role).toBe('user');
  });

  it('PATCH /users/me 不可自助提权（role 不在 PATCHABLE，静默忽略）', async () => {
    const user = store.createUser({ phone: '+8613800138000' });
    const res = (await users.patchMe(user.id, {
      nickname: '想提权',
      role: 'admin',
    } as unknown as PatchUserDto)) as { user: { nickname: string; role: string } };
    expect(res.user.nickname).toBe('想提权'); // 正常字段生效
    expect(res.user.role).toBe('user'); // role 被忽略
  });

  it('管理台 setUserRole：user→admin→user 幂等；列表视图带 role；不存在 → NOT_FOUND', async () => {
    const user = store.createUser({ phone: '+8613800138000', nickname: '小明' });

    const promoted = await adminUsers.setUserRole(user.id, 'admin');
    expect(promoted.role).toBe('admin');
    const again = await adminUsers.setUserRole(user.id, 'admin');
    expect(again.role).toBe('admin'); // 幂等

    const list = await adminUsers.listUsers('小明', 1, 20);
    expect(list.items[0]?.role).toBe('admin');

    const demoted = await adminUsers.setUserRole(user.id, 'user');
    expect(demoted.role).toBe('user');
    await expect(adminUsers.setUserRole('u_not_exist', 'admin')).rejects.toThrow(
      expect.objectContaining({ code: 'NOT_FOUND' }) as unknown as Error,
    );
  });

  it('审核留痕：approve/reject 落 reviewedBy（移动端审批传用户 id），未审核为 null', async () => {
    const owner = store.createUser({ phone: '+8613800138000' });
    const custom = (await food.createCustomFood(owner.id, {
      clientRequestId: randomUUID(),
      nameZh: '留痕臊子面',
      per100g: { kcal: 200, proteinG: 8, carbG: 30, fatG: 5 },
      source: 'manual',
    })) as { id: string };
    const candidate = (await food.contributeCustomFood(owner.id, custom.id, {
      clientRequestId: randomUUID(),
    })) as { id: string; reviewedBy: string | null };
    expect(candidate.reviewedBy).toBeNull();

    const reviewer = store.createUser({ phone: '+8613800138001', role: 'admin' });
    const approved = (await food.reviewFoodCandidate(candidate.id, { action: 'approve' }, reviewer.id)) as {
      status: string;
      reviewedBy: string | null;
    };
    expect(approved.status).toBe('approved');
    expect(approved.reviewedBy).toBe(reviewer.id);

    // reject 路径留痕（独立候选）
    const custom2 = (await food.createCustomFood(owner.id, {
      clientRequestId: randomUUID(),
      nameZh: '留痕油泼面',
      per100g: { kcal: 180, proteinG: 6, carbG: 28, fatG: 4 },
      source: 'manual',
    })) as { id: string };
    const candidate2 = (await food.contributeCustomFood(owner.id, custom2.id, {
      clientRequestId: randomUUID(),
    })) as { id: string };
    const rejected = (await food.reviewFoodCandidate(
      candidate2.id,
      { action: 'reject', reason: '营养数据存疑' },
      reviewer.id,
    )) as { status: string; reviewedBy: string | null };
    expect(rejected.status).toBe('rejected');
    expect(rejected.reviewedBy).toBe(reviewer.id);

    // 管理端 x-admin-token 兜底（reviewedBy 不传）保持 null，不破坏旧行为
    const custom3 = (await food.createCustomFood(owner.id, {
      clientRequestId: randomUUID(),
      nameZh: '留痕裤带面',
      per100g: { kcal: 190, proteinG: 7, carbG: 29, fatG: 4 },
      source: 'manual',
    })) as { id: string };
    const candidate3 = (await food.contributeCustomFood(owner.id, custom3.id, {
      clientRequestId: randomUUID(),
    })) as { id: string };
    const legacy = (await food.reviewFoodCandidate(candidate3.id, { action: 'approve' })) as {
      reviewedBy: string | null;
    };
    expect(legacy.reviewedBy).toBeNull();
  });
});

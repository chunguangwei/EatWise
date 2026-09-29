import { Inject, Injectable, Logger } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { UserEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver, UserDataExport } from '../common/store/store-driver';
import { maskPhone } from '../common/utils/phone.util';
import { computeTargets } from '../nutrition/nutrition.rules';
import { PatchUserDto } from './user.dto';

const DELETION_COOLING_OFF_DAYS = 7; // 删除冷静期 7 天〔假设，待法务确认 D-18 / 合规 §4.3〕

const PATCHABLE = [
  'nickname',
  'gender',
  'birthYear',
  'heightCm',
  'weightKg',
  'activityLevel',
  'goal',
  'targetWeightKg',
  'targetDate',
  'timezone',
  'locale',
  'themePref',
  'accessibilityPrefs',
  'settingsPrefs',
  'onboardingStatus',
] as const;

@Injectable()
export class UserService {
  private readonly logger = new Logger('UserService');

  constructor(@Inject(STORE_DRIVER) private readonly driver: StoreDriver) {}

  async getMe(userId: string) {
    const user = await this.mustGet(userId);
    return { user: this.userView(user), nutritionTargets: computeTargets(user) };
  }

  /** U2 修改资料：字段级 LWW（服务端 updatedAt 仲裁，无 409），触发营养目标重算（D-04） */
  async patchMe(userId: string, body: PatchUserDto) {
    const existing = await this.mustGet(userId);
    const patch: Record<string, unknown> = {};
    for (const key of PATCHABLE) {
      if (body[key] !== undefined) patch[key] = body[key];
    }
    // targetDate 只存日期口径：DTO 收 YYYY-MM-DD 字符串，落库前归一化为 UTC 零点
    // （null 透传 = 清空目标）。
    if (typeof patch['targetDate'] === 'string') {
      patch['targetDate'] = new Date(`${patch['targetDate']}T00:00:00.000Z`);
    }
    // settingsPrefs 键级合并（2026-09-29 拍板，替代整包 LWW 替换）：上行包
    // 的键覆盖服务端同键，未上行的键保留——双端各改不同键不再互相覆盖
    // （旧端整包推送天然兼容：它上行的就是它掌握的全部键）。键集合只增，
    // 不提供删键语义。
    // LWW 时间戳由服务端时钟统一打（忽略客户端自报值）：各端设备墙钟有偏差，
    // 超前设备的旧偏好会永久压制他端改动（走查 L6）。
    if (patch['settingsPrefs'] && typeof patch['settingsPrefs'] === 'object') {
      const current = (existing.settingsPrefs ?? {}) as Record<string, unknown>;
      patch['settingsPrefs'] = {
        ...current,
        ...(patch['settingsPrefs'] as Record<string, unknown>),
        syncedAt: new Date().toISOString(),
      };
    }
    // version+1 / updatedAt=服务端时钟 由驱动赋值（客户端传入的 updatedAt 忽略，防腐层）
    const user = await this.driver.updateUserProfile(userId, patch);
    return { user: this.userView(user), nutritionTargets: computeTargets(user) };
  }

  /**
   * U3 数据导出（合规 §4.2 查阅复制权，D-18）：聚合该用户全量个人数据
   *（Profile/FoodEntry/FastingPlan/FastingRecord/Streak/Post）返回 JSON。
   * 只读操作，天然幂等；导出包内含明文手机号（本人数据，PIPL §44/45）。
   */
  async exportMe(userId: string): Promise<UserDataExport> {
    await this.mustGet(userId);
    const bundle = await this.driver.collectUserExport(userId);
    if (!bundle) throw err.notFound();
    return bundle;
  }

  /**
   * U5 申请删除账号（合规 §4.3，D-18）：进入 deletionStatus=pending +
   * scheduledDeletionAt=now+7天；立即吊销全部 refresh token（登出所有会话、
   * 冻结数据上报）。幂等：重复申请返回当前删除任务状态（契约 §四）。
   */
  async requestDeletion(userId: string) {
    const user = await this.mustGet(userId);
    if (user.deletionStatus === 'pending') return this.deletionView(user);
    const scheduled = new Date(new Date().getTime() + DELETION_COOLING_OFF_DAYS * 24 * 3600 * 1000);
    const updated = await this.driver.updateUserDeletion(userId, 'pending', scheduled);
    await this.revokeAllTokens(userId);
    return this.deletionView(updated);
  }

  /**
   * UGC 屏蔽（App Store 条例 1.2）：屏蔽后对方的帖不再出现在我的信息流，
   * 双向任一方存在屏蔽时互动（点赞/举报/详情）404（见 SocialService）。
   * 幂等：重复屏蔽返回当前状态；不能屏蔽自己（400）。
   */
  async blockUser(userId: string, targetId: string) {
    if (userId === targetId) throw err.validation({ userId: 'cannot block self' });
    const target = await this.driver.findUserById(targetId);
    if (!target || target.deletedAt) throw err.notFound();
    const block = await this.driver.addUserBlock(userId, targetId);
    return { blocked: true, blockedUserId: block.blockedUserId };
  }

  /** 解除屏蔽（幂等：无屏蔽关系也返回 200） */
  async unblockUser(userId: string, targetId: string) {
    await this.driver.removeUserBlock(userId, targetId);
    return { blocked: false, blockedUserId: targetId };
  }

  /** 我屏蔽的用户列表（管理页用；带昵称，按屏蔽时间倒序由调用方不要求则按 id 序） */
  async listBlockedUsers(userId: string) {
    const ids = await this.driver.listUserBlockedIds(userId);
    const items = await Promise.all(
      ids.map(async (id) => {
        const target = await this.driver.findUserById(id);
        return { userId: id, nickname: target?.nickname ?? null };
      }),
    );
    return { items };
  }

  /** U6 撤销删除申请（冷静期内）；幂等：非 pending 直接返回当前状态 */
  async cancelDeletion(userId: string) {
    const user = await this.mustGet(userId);
    if (user.deletionStatus !== 'pending') return this.deletionView(user);
    return this.deletionView(await this.driver.updateUserDeletion(userId, null, null));
  }

  /**
   * 到期删除扫描（DeletionScheduler 定时调用）：冷静期满的用户执行
   * 物理删除个人数据 + UGC 匿名化（合规 §4.3：结束后 ≤24h 完成）。
   */
  async executeDueDeletions(now = new Date()): Promise<string[]> {
    const due = await this.driver.listDueDeletionUserIds(now);
    const purged: string[] = [];
    for (const userId of due) {
      const report = await this.driver.purgeUserData(userId);
      purged.push(userId);
      this.logger.log(
        `账号到期删除完成 user=${userId}：entries=${report.foodEntries} ` +
          `fasting=${report.fastingRecords} postsAnonymized=${report.postsAnonymized}`,
      );
    }
    return purged;
  }

  private async revokeAllTokens(userId: string) {
    await this.driver.revokeUserRefreshTokens(userId);
  }

  private deletionView(user: UserEntity) {
    return {
      deletionStatus: user.deletionStatus,
      scheduledDeletionAt: user.scheduledDeletionAt?.toISOString() ?? null,
      coolingOffDays: DELETION_COOLING_OFF_DAYS,
    };
  }

  private async mustGet(userId: string): Promise<UserEntity> {
    const user = await this.driver.findUserById(userId);
    if (!user || user.deletedAt) throw err.notFound();
    return user;
  }

  private userView(u: UserEntity) {
    return {
      id: u.id,
      username: u.username, // D-13 v2：账号密码为主路径，客户端账号标识优先展示
      phone: maskPhone(u.phone), // 对外响应脱敏（合规 §6），明文仅出现在 U3 本人导出包
      nickname: u.nickname,
      avatarUrl: null,
      gender: u.gender,
      birthYear: u.birthYear,
      heightCm: u.heightCm,
      weightKg: u.weightKg,
      activityLevel: u.activityLevel,
      goal: u.goal,
      targetWeightKg: u.targetWeightKg,
      // 对外只暴露日期部分（YYYY-MM-DD），与入库口径一致
      targetDate: u.targetDate?.toISOString().slice(0, 10) ?? null,
      locale: u.locale,
      timezone: u.timezone,
      themePref: u.themePref,
      accessibilityPrefs: u.accessibilityPrefs,
      settingsPrefs: u.settingsPrefs,
      onboardingStatus: u.onboardingStatus,
      role: u.role, // 用户角色（移动端审批中心入口门控；本人不可改，管理台设置）
      deletionStatus: u.deletionStatus,
      scheduledDeletionAt: u.scheduledDeletionAt?.toISOString() ?? null,
      version: u.version,
    };
  }
}

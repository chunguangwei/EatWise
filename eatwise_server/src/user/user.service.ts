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
    await this.mustGet(userId);
    const patch: Record<string, unknown> = {};
    for (const key of PATCHABLE) {
      if (body[key] !== undefined) patch[key] = body[key];
    }
    // targetDate 只存日期口径：DTO 收 YYYY-MM-DD 字符串，落库前归一化为 UTC 零点
    // （null 透传 = 清空目标）。
    if (typeof patch['targetDate'] === 'string') {
      patch['targetDate'] = new Date(`${patch['targetDate']}T00:00:00.000Z`);
    }
    // settingsPrefs 的 LWW 时间戳由服务端时钟统一打（忽略客户端自报值）：
    // 各端设备墙钟有偏差，超前设备的旧偏好会永久压制他端改动（走查 L6）。
    if (patch['settingsPrefs'] && typeof patch['settingsPrefs'] === 'object') {
      patch['settingsPrefs'] = {
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

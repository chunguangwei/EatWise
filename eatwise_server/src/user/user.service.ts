import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore, UserEntity } from '../common/store/data-store';
import { computeTargets } from '../nutrition/nutrition.rules';

const PATCHABLE = [
  'nickname',
  'gender',
  'birthYear',
  'heightCm',
  'weightKg',
  'activityLevel',
  'goal',
  'timezone',
  'locale',
  'themePref',
  'accessibilityPrefs',
] as const;

@Injectable()
export class UserService {
  constructor(private readonly store: DataStore) {}

  getMe(userId: string) {
    const user = this.mustGet(userId);
    return { user: this.userView(user), nutritionTargets: computeTargets(user) };
  }

  /** U2 修改资料：字段级 LWW（服务端 updatedAt 仲裁，无 409），触发营养目标重算（D-04） */
  patchMe(userId: string, body: Record<string, unknown>) {
    const user = this.mustGet(userId);
    for (const key of PATCHABLE) {
      if (body[key] !== undefined) (user as unknown as Record<string, unknown>)[key] = body[key];
    }
    user.version += 1;
    user.updatedAt = new Date(); // 服务端时钟赋值，客户端传入的 updatedAt 忽略（防腐层）
    return { user: this.userView(user), nutritionTargets: computeTargets(user) };
  }

  private mustGet(userId: string): UserEntity {
    const user = this.store.users.get(userId);
    if (!user || user.deletedAt) throw err.notFound();
    return user;
  }

  private userView(u: UserEntity) {
    return {
      id: u.id,
      nickname: u.nickname,
      avatarUrl: null,
      gender: u.gender,
      birthYear: u.birthYear,
      heightCm: u.heightCm,
      weightKg: u.weightKg,
      activityLevel: u.activityLevel,
      goal: u.goal,
      locale: u.locale,
      timezone: u.timezone,
      themePref: u.themePref,
      accessibilityPrefs: u.accessibilityPrefs,
      onboardingStatus: u.onboardingStatus,
      version: u.version,
    };
  }
}

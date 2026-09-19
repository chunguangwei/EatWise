import { Inject, Injectable } from '@nestjs/common';
import { UserEntity, UserRoleName } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { maskPhone } from '../common/utils/phone.util';

/** 管理端用户列表项（phone 脱敏，合规 §6；User 无 lastActiveAt 类字段，不含） */
export interface AdminUserView {
  id: string;
  username: string | null;
  nickname: string | null;
  phone: string | null; // 脱敏（maskPhone），严禁明文
  goal: string | null;
  role: UserRoleName; // user / admin（移动端审批中心入口；PATCH :id/role 设置）
  onboardingStatus: string;
  deletionStatus: string | null;
  createdAt: string;
}

/**
 * 管理端注册用户查看（只读）。数据走 StoreDriver（双驱动同口径：keyword 过滤与
 * 排序在驱动层，与 listFoodCandidates 同模式——驱动返回过滤后全集，此处页码分页切片）。
 */
@Injectable()
export class AdminUsersService {
  constructor(@Inject(STORE_DRIVER) private readonly driver: StoreDriver) {}

  /** 页码分页（page 从 1 起，pageSize ≤100）；keyword 模糊匹配 username/phone/nickname */
  async listUsers(keyword: string | undefined, page = 1, pageSize = 20) {
    const p = Math.max(1, page);
    const size = Math.min(100, Math.max(1, pageSize));
    const all = await this.driver.listUsers(keyword);
    const offset = (p - 1) * size;
    return {
      items: all.slice(offset, offset + size).map((u) => this.view(u)),
      total: all.length,
      page: p,
      pageSize: size,
    };
  }

  /** 设置用户角色（管理台用户列表；仅 admin 可调，幂等：重复设置同值返回当前态） */
  async setUserRole(userId: string, role: UserRoleName) {
    const user = await this.driver.updateUserRole(userId, role);
    return this.view(user);
  }

  private view(u: UserEntity): AdminUserView {
    return {
      id: u.id,
      username: u.username,
      nickname: u.nickname,
      phone: maskPhone(u.phone), // 脱敏后出层，明文不出 Service
      goal: u.goal,
      role: u.role,
      onboardingStatus: u.onboardingStatus,
      deletionStatus: u.deletionStatus,
      createdAt: u.createdAt.toISOString(),
    };
  }
}

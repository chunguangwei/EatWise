import { SetMetadata } from '@nestjs/common';
import { AdminRoleName } from '../common/store/data-store';

export const ADMIN_ROLE_KEY = 'adminRole';

/**
 * 管理端点最低角色要求（角色层级：admin > reviewer）。
 * - reviewer：食物候选/打卡审核、食物库搜索端点（admin 亦可）
 * - admin：仅管理员端点（食物库删除 AdminFoodsController.remove、用户角色设置）
 */
export const AdminRole = (role: AdminRoleName) => SetMetadata(ADMIN_ROLE_KEY, role);

/** 角色层级是否满足（admin 覆盖 reviewer 的全部权限） */
export function roleSatisfies(actual: AdminRoleName, required: AdminRoleName): boolean {
  if (required === 'reviewer') return true; // admin / reviewer 均可
  return actual === 'admin';
}

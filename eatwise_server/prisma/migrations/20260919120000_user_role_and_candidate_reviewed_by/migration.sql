-- 用户角色体系 + 移动端审批：users 增 role（user/admin，默认 user，管理台设置）；
-- food_candidates 增 reviewedBy（审核留痕：终审执行者 id，管理端管理员账号或移动端审批用户）。

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "role" TEXT NOT NULL DEFAULT 'user';

-- AlterTable
ALTER TABLE "food_candidates" ADD COLUMN     "reviewedBy" TEXT;

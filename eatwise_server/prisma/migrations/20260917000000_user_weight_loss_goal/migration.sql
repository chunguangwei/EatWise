-- 阶段 B 减重目标：users 增 targetWeightKg（目标体重，kg）/ targetDate（目标日期，
-- 只存日期口径 UTC 零点）——有目标体重+日期时减脂目标热量由固定 TDEE×0.8 切换为
-- 缺口法（1 kg ≈ 7700 kcal，周速率 0.1–1.0 kg 安全夹取），规格文档新章节同步。
-- AlterTable
ALTER TABLE "users" ADD COLUMN     "targetWeightKg" DOUBLE PRECISION,
ADD COLUMN     "targetDate" TIMESTAMP(3);

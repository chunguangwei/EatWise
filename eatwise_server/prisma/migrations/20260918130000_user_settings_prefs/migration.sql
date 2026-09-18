-- D-21 用户级偏好跨端同步：users 增 settingsPrefs（JSON 同步包：
-- locale/theme/weightUnit/burnGoalKcal/stepsGoal + syncedAt，缺键跳过，字段级 LWW）。
-- AlterTable
ALTER TABLE "users" ADD COLUMN     "settingsPrefs" JSONB;

-- 用户自定义食物：个人库条目（isCustom + createdByUserId 可见性过滤，仅创建者可见，参与 K1 搜索）。
ALTER TABLE "foods" ADD COLUMN "isCustom" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "foods" ADD COLUMN "createdByUserId" TEXT;

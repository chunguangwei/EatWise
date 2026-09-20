-- 匿名发帖（2026-09-20 产品需求）：帖子行加 anonymous（作者遮蔽开关）+ avatarId（客户端预设头像库索引，发帖时选定即固定，不随用户资料变）。
-- 遮蔽在服务端视图层（postViews）做：非作者查看时不下发 author.id/nickname。
-- AlterTable
ALTER TABLE "posts" ADD COLUMN "anonymous" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "posts" ADD COLUMN "avatarId" INTEGER;

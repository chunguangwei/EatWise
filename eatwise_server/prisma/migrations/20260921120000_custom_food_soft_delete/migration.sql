-- 自定义食物删除能力（PATCH/DELETE /foods/custom/:id）：foods 增 deletedAt 软删 tombstone。
-- 仅自定义行删除时使用（共享库行不删）；读路径统一 deletedAt IS NULL 过滤，
-- 引用该食物的 food_entries 由服务端级联软删（sync/pull 下行 tombstone）。
-- AlterTable
ALTER TABLE "foods" ADD COLUMN     "deletedAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "foods_deletedAt_idx" ON "foods"("deletedAt");

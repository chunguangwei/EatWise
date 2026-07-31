-- 共享食物候选审核池（食物库扩充第三层：用户自定义食物经审核晋升为共享库，先审后发 D-17）。
-- approve 时服务端把对应 foods 行 isCustom 置 false、source 置 'community'，createdByUserId 保留溯源。
CREATE TABLE "food_candidates" (
    "id" TEXT NOT NULL,
    "foodId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reason" TEXT,
    "clientRequestId" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "food_candidates_pkey" PRIMARY KEY ("id")
);

-- 审核队列按状态过滤 + 先入先审
CREATE INDEX "food_candidates_status_createdAt_idx" ON "food_candidates"("status", "createdAt");

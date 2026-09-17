-- 阶段 C 体重管理闭环：weight_logs 表（体重记录同步化）。同日覆写由应用层
-- （userId+date 查重后 update/create）实现；clientRequestId 幂等（D-20），
-- bodyFatPct 可空，deletedAt 软删 tombstone——口径对齐 water_logs。
-- CreateTable
CREATE TABLE "weight_logs" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "clientRequestId" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "weightKg" DOUBLE PRECISION NOT NULL,
    "bodyFatPct" DOUBLE PRECISION,
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "weight_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "weight_logs_userId_clientRequestId_key" ON "weight_logs"("userId", "clientRequestId");

-- CreateIndex
CREATE INDEX "weight_logs_userId_date_idx" ON "weight_logs"("userId", "date");

-- AddForeignKey
ALTER TABLE "weight_logs" ADD CONSTRAINT "weight_logs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

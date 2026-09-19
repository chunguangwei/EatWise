-- 运动记录上行（手动记运动/截图导入，2026-09-19 产品拍板）：exercise_logs 表。
-- 轻量两态同步（仅 create/软删，无 update——运动记录无编辑场景，改 = 删了重记），
-- clientRequestId 幂等（D-20），deletedAt 软删 tombstone——口径对齐 water_logs。
-- 合规边界：仅用户主动录入/截图确认的记录；系统健康数据（HealthKit/
-- Health Connect 实时步数）不出端、不落本表。
-- CreateTable
CREATE TABLE "exercise_logs" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "clientRequestId" TEXT NOT NULL,
    "typeKey" TEXT NOT NULL,
    "durationMin" INTEGER NOT NULL,
    "kcal" DOUBLE PRECISION NOT NULL,
    "steps" INTEGER,
    "source" TEXT,
    "loggedAt" TIMESTAMP(3) NOT NULL,
    "localDate" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "exercise_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "exercise_logs_userId_clientRequestId_key" ON "exercise_logs"("userId", "clientRequestId");

-- CreateIndex
CREATE INDEX "exercise_logs_userId_updatedAt_id_idx" ON "exercise_logs"("userId", "updatedAt", "id");

-- AddForeignKey
ALTER TABLE "exercise_logs" ADD CONSTRAINT "exercise_logs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

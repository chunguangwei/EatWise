-- 条码商品众包回传（带营养表佐证照片）：
-- food_candidates 增 kind/barcode/evidenceImageUrl（条码补录贡献入审核池，管理员对照照片「对答案」）；
-- foods 增 barcode（条码候选 approve 晋升时写入，后续扫码先命中自有库再代理 OFF）。
-- AlterTable
ALTER TABLE "foods" ADD COLUMN     "barcode" TEXT;

-- AlterTable
ALTER TABLE "food_candidates" ADD COLUMN     "barcode" TEXT,
ADD COLUMN     "evidenceImageUrl" TEXT,
ADD COLUMN     "kind" TEXT NOT NULL DEFAULT 'custom';

-- CreateIndex
CREATE INDEX "foods_barcode_idx" ON "foods"("barcode");

-- CreateIndex
CREATE INDEX "food_candidates_barcode_idx" ON "food_candidates"("barcode");

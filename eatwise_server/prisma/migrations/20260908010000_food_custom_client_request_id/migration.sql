-- 自定义食物幂等键落库：foods.clientRequestId（K2 创建幂等，D-20；
-- 对齐内存 CustomFoodEntity.clientRequestId，自定义食物行方有值）。
ALTER TABLE "foods" ADD COLUMN "clientRequestId" TEXT;


-- 食物数据纠错（食物详情页「数据有误？」入口）：
-- food_candidates 增 suggestion（kind=correction 时存建议名称/每 100g 营养，
-- 审核台与原值对照展示，approve 后应用到共享食物行）。
-- AlterTable
ALTER TABLE "food_candidates" ADD COLUMN     "suggestion" JSONB;

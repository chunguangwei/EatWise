# features/nutrition/application — M4 数据页应用层（docs/specs/规格-营养规则-TDEE公式与信号灯阈值-v1.0.md）

- `nutrition_data_controller.dart`：日期切换（不可超今天）+ drift DailyNutritionCaches 聚合缓存接线（`NutritionDataSource` 端口）+ 信号灯判定/总结语气/近 7 日趋势 provider。
- `advice_text.dart`：建议模板 key → 双语模板文案解析（营养素 × 落区 × 餐段，§4）。

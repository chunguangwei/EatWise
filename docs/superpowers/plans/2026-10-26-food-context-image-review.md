# 食物说明与图片审核 Implementation Plan

> **For agentic workers:** root 负责集成、客户端发布反馈、串行 Flutter 验证和发布；独立代理负责详情展示、服务端审核和只读设备核查。

**Goal:** 让食物说明与份量、来源相符，让图片帖进入可用的人工审核流程，完成可执行的真机专项并发布 1.17.11+141。

**Architecture:** 延续 feature-first 和语义设计 Token；份量计算纯函数化，审核复用 StoreDriver 事务和现有管理端。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2、NestJS、Prisma/PostgreSQL、XCUITest。

**Spec:** docs/superpowers/specs/2026-10-26-food-context-image-review-design.md

## Constraints and Review Focus

- Flutter 测试和构建只由 root 串行运行；使用仓库 SDK 和 dart analyze。
- 不写生产演示数据，不卸载生产应用，不伪造来源或 AI 能力验收。
- 份量非法/目标为零不得出现无穷值或错误百分比；来源和大字体布局须验证。
- 图片 pending 的作者/访客/管理员视图、幂等、故障回滚和审核后可见性必须一致。
- 原生输入测试不得靠重新点焦点掩盖连接中断。

## Tasks

- [x] App 详情：新增失败回归 → 份量占比与来源替代信号徽标 → 专项绿 → 独立复核。
  Files: food_detail_sheet.dart、相关 domain、food_detail_sheet_test.dart、i18n 双语及 slang 生成。
- [x] Server：新增图片 pending/纯文字 approved、权限、审核/删除/事务/幂等测试 → 最小实现 → lint/build/unit/e2e/PG。
  Files: social.service.ts、相关 tests；复用现有人工审核数据结构。
- [x] App 发布反馈：新增带图说明/按钮/pending 返回提示回归 → 实现；已存在 PostCard 待审状态保持可见。
  Files: compose_page.dart、compose_page_test.dart、social_test_fakes.dart、双语键。
- [ ] 安全真机验证：确认独立 bundle/本地服务/现有样本条件，执行可验证场景；保存未验边界。
- [ ] 同步 D-05/D-17、发布事实文案及验收文档；format/analyze/全量 App 门禁；独立审查。
- [ ] 更新版本，提交推送，CI、后端备份部署、GitHub APK/备用源校验、iOS 构建覆盖安装与设备回读。

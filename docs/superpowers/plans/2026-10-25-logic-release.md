# v1.17.10 逻辑修复与发布 Implementation Plan

> **For agentic workers:** Use the assigned independent implementation tasks below; root integrates, verifies, and releases under the user's existing authorization.

**Goal:** 修复 1e40ce4 审查确认的十项逻辑问题，发布 1.17.10+140。

**Architecture:** 保留 feature-first 架构。记录仓储持久保存首次创建的未知结果及后续意图；请求与同步绑定会话；服务端按既有事务驱动串行关键状态转换；自然日计算与真实时长分离。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2、drift SQLite、NestJS、Prisma/PostgreSQL。

**Spec:** AGENTS.md、docs/00-决策记录-开放问题拍板-v1.0.md（D-08、D-12、D-20）及本轮审查十项发现。

## Global Constraints

- Flutter 使用仓库 SDK，分析命令为 dart analyze；Flutter 测试和构建串行。
- 保留用户记录，不卸载应用、不清库；iOS release 必须使用生产 API 地址。
- 原生 UI 走查遵循用户此前指示跳过。
- 不更改营养目标及能量口径，不引入与修复无关的功能。

## Review Focus

- 创建已经提交但响应丢失：重启、编辑、删除仍只有一条最终记录。
- 任意 await 期间换号：旧请求和旧响应不能影响新账号。
- 删除中断：列表与日聚合恢复一致。
- 并发审核和方案更新：两种 StoreDriver 保持一致且无半提交。
- 夏令时前后：逐日序列无重复/遗漏，周月汇总包含正确日期。

## Tasks

- [x] 记录仓储：先将 /tmp 的三项 SQLite 复现改为正式失败回归；实现持久创建对账、删除/聚合事务及恢复测试。
- [x] 会话隔离：为迟到 401、迟到 refresh、旧同步上下行补测试；请求绑定会话，丢弃失效任务和响应。
- [x] 服务端：回归 D-08 延长判定、拒绝客户端 makeup、并发方案唯一当前状态、审核事务；修复后跑 unit/e2e/真实 PostgreSQL。
- [x] 自然日：补 DST 日期翻页和趋势统计回归，统一 calendar-day 运算；不替换真实持续时长。
- [x] 集成：dart format、dart analyze 零 issue、flutter test 全绿；server lint/build/test/e2e；独立复核变更。
- [x] 发布：版本与说明、提交 push、CI 门禁、后端备份部署和健康检查、tag/GitHub APK、备用下载核验、iOS release 构建与可用真机覆盖更新。
- [x] 保存实际发布结果与未验范围，报告真实可用的版本和链接。

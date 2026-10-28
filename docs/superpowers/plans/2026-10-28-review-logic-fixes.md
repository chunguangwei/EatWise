# Review Logic Fixes Implementation Plan

> **For agentic workers:** 按独立领域使用 dispatching-parallel-agents；root 集成并串行执行 Flutter 门禁，最终执行 requesting-code-review。已批准的审查描述即实施范围，不重复请求确认。

**Goal:** 修复已复现的食品同步、举报结案、报告归属、时区和发布稿件问题。
**Architecture:** 沿用 feature-first / StoreDriver；自定义食品使用持久化创建快照与 dirty 状态，旧回执按代际对账；原生时区桥接供统一 Provider 消费。
**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2、drift、Swift/Kotlin、NestJS、PostgreSQL。
**Spec:** docs/superpowers/specs/2026-10-28-review-logic-fixes-design.md

## Global Constraints

- Flutter 测试、生成、预览及原生构建由 root 串行执行。
- 数据迁移保留所有现有记录；旧 pending 身份不丢弃。
- 用户要求 HTTPS/SSH 超时暂不处理：不继续线上连接排查或生产业务写入。
- i18n 只改两份 JSON，以 dart run slang 生成。

## Review Focus

- 创建成功但 ACK 丢失、重启后编辑：原身份最终只生成一行。
- create/PATCH 在途编辑/删除和下行同 id 碰撞：保留最新意图与引用。
- 已删/已共享 404、账号切换和失败计数：不能误戴徽标或改错代际。
- 举报确认下架后再次举报/恢复/重复审核：保留审计并正确出入队。
- 旅行/DST、冻结周期跨日、发布失败回退：不丢锚点或草稿。

## Tasks

- [x] 1. 自定义食品对账与404纠偏：先复制已复现3例到正式回归并补重启/离线 PATCH/代际和迁移，再实现最小状态机、DAO及下行保护；root 生成 drift 后串行验证。Files: custom_food_repository.dart、food_dao.dart、tables.dart、database.dart、remote_record_sync.dart、对应测试。Interface: 维持 save/update/retryPending 对外形状，已有 customSyncPending 统一表示待上行；具体新增列由实现者审查确定并记录。
- [x] 2. 举报复核闭环：先失败回归（举报→确认下架→出队/筛选，回滚/重复/恢复），后实现同帖锁内决定、保留报告历史及管理台入口。Files: social.service.ts、store drivers、admin console、服务端测试；不新增客户端必需API。
- [x] 3. 系统时区：先 MethodChannel fake + 时间标识/DST/前台变更回归，后实现 Android/iOS 桥接、bootstrap 与 Provider刷新/重排。Files: core/time、main.dart、onboarding_controller.dart、原生 AppDelegate/MainActivity、相关测试。Interface: deviceLocationProvider 返回当前已校验 tz.Location，现有调用方保持兼容。
- [x] 4. 报告归属：先跨日/首日明日归属/新周期回归，后通过计时器语义投影监听正式 attributionPreview，只标真实归属日。Files: reports_controller.dart、报告测试。Consumes: 现有 fastingTimerControllerProvider；时区任务不改该公开形状。
- [x] 5. 发布稿件：先在途编辑/图片/匿名/头像/返回及失败恢复回归，后冻结所有稿件控件并保留失败草稿。Files: compose_page.dart、compose_page_test.dart、必要假服务。
- [x] 6. 集成：format/analyze/全量 App、服务端 lint/build/unit/e2e/可用本机PG、Android debug 和 iOS 构建；独立复核；更新 QA/AGENTS，提交 GitHub。不得把未部署服务器或未完成真机项目写成已上线。

## 验收

2026-10-28：App 1844 项全绿、dart analyze 零 issue；Android debug / iOS release no-codesign 构建通过；服务端384单测、170 e2e、476 PostgreSQL通过。独立复核发现均已修复。交付含代码与GitHub同步，不含生产服务端部署或真机安装；详见 docs/qa/逻辑复核修复-2026-10-28.md。

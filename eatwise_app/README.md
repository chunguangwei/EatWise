# eatwise_app

明食 · EatWise 客户端（Flutter，iOS / Android 双端，中英双语）。

开发指南、环境要求、踩坑记录见仓库根目录：

- [README.md](../README.md)——快速开始、发版与更新、当前状态
- [AGENTS.md](../AGENTS.md)——开发命令与硬性规则速查

常用命令（SDK 在 `../.tooling/flutter/bin`）：

```bash
export PATH="$PWD/../.tooling/flutter/bin:$PATH"
flutter pub get && dart run slang && dart run build_runner build
dart analyze && flutter test
```

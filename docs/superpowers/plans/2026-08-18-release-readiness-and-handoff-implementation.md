# MihomoSurgeBridge 发布前修复与交接实施计划

日期：2026-08-18
依据：`docs/superpowers/specs/2026-08-18-release-readiness-and-handoff-design.md`

## 任务 1：日志时区

- 新增独立的日志时间格式化单元，使用调用时的 `TimeZone.autoupdatingCurrent`。
- `AppLogger` 使用该单元写入 ISO 8601 本地时间。
- 增加固定 `+08:00` 时区的回归测试并接入 `scripts/test.sh`。

## 任务 2：单一管理窗口

- 将主场景从 `WindowGroup` 改为单例 `Window`。
- 保持菜单栏 `openWindow(id: "main")`、应用激活和 Dock 显隐逻辑。
- 增加场景声明回归检查，防止以后改回可创建多个窗口的结构。

## 任务 3：版本和文档

- 版本提升到 `0.1.4 (5)`。
- 精简 README，清楚说明用途、使用流程、限制、构建和数据位置。
- 新增完整方案设计与开发交接文档，以当前实现为准整理已做、明确不做和可迭代项。
- 新增后续迭代交接模板，规定每轮开发必须留下的上下文与验证记录。

## 任务 4：验证与发布

- 运行全部自检和 debug 构建。
- 生成 arm64 release 应用与 ZIP，核验版本、架构、签名和 ZIP 解压后的签名。
- 检查完整差异并提交本次改动。
- 确认 GitHub 远端状态，创建或连接公开的 `vengence/MihomoSurgeBridge`，推送 `main`。
- 发布后记录仓库地址、提交、构建产物和校验值。

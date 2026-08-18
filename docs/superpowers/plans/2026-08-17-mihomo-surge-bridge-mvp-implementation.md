# MihomoSurgeBridge MVP 实施计划

设计基线：`docs/superpowers/specs/2026-08-17-mihomo-surge-bridge-mvp-design.md`

## 交付目标

在本地生成可双击运行的 `MihomoSurgeBridge.app`。应用能够保存订阅、从 YAML 缓存/网络提取 SSR 节点、生成 Mihomo 与 Surge 配置、启动和停止 Mihomo，并提供简体中文 SwiftUI 管理界面和菜单栏入口。

## 阶段 1：工程与 Core

1. 创建 SwiftPM manifest，目标为 macOS 13、Swift 6。
2. 添加 Yams 6.x 依赖和 Core/App/Test targets。
3. 实现 Codable 配置模型、SSR 节点规范化模型和默认地区。
4. 实现 YAML 解析、过滤、命名、地区匹配和稳定身份。
5. 实现 Mihomo YAML、Surge policy-path 文件和 `.msbridge` 迁移生成器。
6. 用虚构 fixtures 覆盖核心行为。

验收：`swift test` 中 Core 测试全部通过。

## 阶段 2：本地服务

1. 建立应用目录、JSON 配置、缓存和原子文件写入。
2. 实现订阅 URLSession 下载、超时、大小限制和最后成功缓存保护。
3. 实现全量生成事务与变化检测。
4. 检测 Homebrew 和应用托管 Mihomo。
5. 实现固定端口检查、Mihomo 配置校验、启动、停止和受控重启。
6. 实现一小时调度、启动立即刷新、睡眠恢复补刷。

验收：服务测试使用临时目录和虚构数据，不访问真实订阅或现有原型。

## 阶段 3：SwiftUI MVP

1. 创建 `@main` 应用、`AppModel`、普通窗口与 `MenuBarExtra`。
2. 实现概览、订阅、地区、输出、设置与诊断五个页面。
3. 实现添加/编辑/删除订阅、更新、过滤预览和状态展示。
4. 实现 Mihomo 启停、来源选择、端口选择和输出目录选择。
5. 实现复制策略组、Finder 显示、日志目录和退出清理。
6. 实现 `SMAppService.mainApp` 登录启动开关。

验收：应用可以在无任何配置时启动；空状态不会崩溃；关闭窗口后菜单栏继续存在。

## 阶段 4：打包与运行验收

1. 编写 `scripts/build-app.sh`，执行 release arm64 构建。
2. 组装 `MihomoSurgeBridge.app/Contents/{MacOS,Resources}` 和 `Info.plist`。
3. 执行临时签名并生成 `.app.zip`。
4. 检查 Mach-O 架构、Bundle Identifier、签名和启动日志。
5. 在独立临时 Application Support 环境完成空配置启动测试。
6. 提供 README，说明运行、添加订阅、安装 Mihomo 和粘贴 Surge 片段。

验收：产物可双击启动；`swift test`、release build、签名验证和启动 smoke test 全部通过。

## 安全边界

- 不读写 `/Users/vengence/Library/Application Support/mihomo-surge/`。
- 不读写现有 LaunchAgent。
- 不读写 Surge `肯德基.conf` 或 `Maying-SSR.conf`。
- 不使用真实订阅 fixture。
- 不创建远程 GitHub 仓库或推送。

## MVP 可接受简化

- 系统服务保持单体应用内的小型类型，不拆成额外 packages。
- 日志只做单文件和基本脱敏。
- 更新失败只保留最后成功缓存，不做历史回滚。
- 首次使用引导可以集成在概览空状态中，不制作独立多步向导。
- 应用托管 Mihomo 安装若无法在离线测试中验证，仍必须提供清晰错误和 Homebrew 路径。

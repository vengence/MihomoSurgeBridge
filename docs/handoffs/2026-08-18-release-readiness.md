# MihomoSurgeBridge 迭代开发交接

## 1. 基本信息

- 日期：2026-08-18
- 版本与构建号：0.1.4（5）
- 分支：`main`
- 最终提交：以本交接文件所在的发布提交为准
- 构建产物：`dist/MihomoSurgeBridge.app.zip`
- ZIP SHA-256：`8961b636750ad28d925d0f16788cfb34952728b20d546c7f40beca228739d709`

## 2. 本次目标

- 修正应用日志使用 UTC 而不是系统时区的问题。
- 修正从菜单栏反复打开多个管理窗口的问题。
- 为首次公开发布整理简洁 README、完整方案设计和后续交接规范。
- 成功标准是新日志包含本地偏移、主界面声明为单例窗口、全部自检和发布构建通过、公开仓库内容完整。

## 3. 已确认的决定

- 日志继续使用 ISO 8601，只把时区改为 `TimeZone.autoupdatingCurrent`；不重写旧日志，也不改变配置 JSON 和 Mihomo 日志。
- 主界面使用 macOS 13 原生单例 `Window`，不增加自建窗口控制器。
- README 只承担项目介绍和快速使用，详细决策集中在长期方案交接文档。
- 后续影响行为、架构或数据格式的迭代先写规格；局部缺陷至少留下根因、改动和测试记录。

## 4. 实际完成

- 新增独立日志时间格式化单元，应用日志跟随系统时区。
  - `Sources/MihomoSurgeBridge/LogTimestampFormatter.swift`
  - `Sources/MihomoSurgeBridge/Stores.swift`
- 将主场景从 `WindowGroup` 改为单例 `Window`。
  - `Sources/MihomoSurgeBridge/MihomoSurgeBridgeApp.swift`
- 增加日志时区和单窗口结构回归检查，并接入统一测试脚本。
  - `Tests/LogTimestampSelfTest/main.swift`
  - `Tests/AppSceneSelfTest/main.swift`
  - `scripts/test.sh`
- 版本提升到 0.1.4（5）。
  - `Resources/Info.plist`
- 重写 README，并新增完整方案交接和迭代交接模板。
  - `README.md`
  - `docs/MihomoSurgeBridge-方案设计与开发交接.md`
  - `docs/迭代开发交接模板.md`

## 5. 明确未做

- 没有改变订阅、代理路由、Surge 输出或配置格式。
- 没有重写历史日志。
- 没有增加多窗口管理器或额外 UI 功能。
- 没有增加 Developer ID 签名、公证、自动更新或 GitHub Release。

## 6. 兼容性和数据影响

- 最低系统版本和架构不变：macOS 13+、Apple Silicon。
- 配置、缓存和 `.msbridge` 格式不变，不需要迁移。
- Mihomo 路由和 Surge 输出不变。
- 新日志时间从 UTC 改为带系统时区偏移的 ISO 8601；旧日志保留原样。
- 没有新增隐私或网络数据收集。

## 7. 验证结果

### 自动检查

- `./scripts/test.sh`：全部通过，包括核心自检、配置检查状态保持、菜单栏图标、日志 `+08:00` 和单例 `Window` 场景。
- debug 完整构建：通过。
- `./scripts/build-app.sh`：release arm64 构建、应用组装、临时签名、ZIP 解压签名复验和架构检查通过。
- ZIP 解压后版本：0.1.4（5）。
- ZIP 解压后架构：arm64。
- ZIP 解压后严格签名验证：通过。

### 人工验收

- 自动界面控制成功启动构建产物，但本机辅助功能通道无法读取该应用窗口状态，因此没有完成菜单栏重复点击的真实 UI 操作。

### 未能验证

- 需要用户用发布 ZIP 进行一次最终操作验收：连续点击菜单栏“打开管理窗口”、最小化后再打开、关闭后再打开，确认始终只有一个管理窗口且 Dock 显隐正确。

## 8. 已知问题和风险

- 当前为临时签名且未公证，其他机器首次打开可能需要 Finder 右键“打开”。
- 文件同步目录可能给未压缩 `.app` 增加 Finder 扩展属性；应分发和安装 ZIP 中的应用，ZIP 解压签名已验证。
- 日志仍没有轮换。
- 发布前发现旧提交作者使用公司邮箱；公开历史前需要决定保留历史还是发布清理后的单提交快照。

## 9. 下一步建议

1. 完成 GitHub 首次公开发布。
2. 用户对 0.1.4 发布包执行单窗口和 Dock 的最终人工验收。
3. 只根据真实使用反馈继续修复，不扩展 MVP 边界。

## 10. 新会话接手说明

- 先阅读 `README.md` 和 `docs/MihomoSurgeBridge-方案设计与开发交接.md`。
- 本轮设计见 `docs/superpowers/specs/2026-08-18-release-readiness-and-handoff-design.md`。
- 本轮实施计划见 `docs/superpowers/plans/2026-08-18-release-readiness-and-handoff-implementation.md`。
- 应用日志位于 `~/Library/Application Support/MihomoSurgeBridge/Logs/app.log`。
- 修改前先检查最新提交、GitHub 远端和用户最终 UI 验收结果。

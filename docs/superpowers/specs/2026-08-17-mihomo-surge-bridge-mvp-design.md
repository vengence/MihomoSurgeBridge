# MihomoSurgeBridge MVP 设计规格

日期：2026-08-17  
状态：已批准  
应用名称：MihomoSurgeBridge  
Bundle Identifier：`com.vengence.MihomoSurgeBridge`

## 1. 目标

交付一个能在 Apple Silicon、macOS 13 及以上系统直接运行的本地 SwiftUI 应用，通过 Mihomo 将 Clash/Mihomo YAML 订阅中的 SSR 节点转换为 Surge 可引用的本地 SOCKS5 策略。

MVP 以个人自用、尽快可用为首要目标。应用不得读取、修改或重载用户的 Surge 配置，也不得改动现有脚本原型、LaunchAgent 或 Surge 主配置。

## 2. 已锁定范围

- 仅支持 Apple Silicon、macOS 13+ 和 Surge for Mac。
- 使用 Swift 6、SwiftUI、Swift Package Manager，不创建 Xcode 工程。
- 普通管理窗口与菜单栏入口共存；关闭窗口不退出应用。
- 支持 Homebrew 已安装的 Mihomo，以及应用托管的 Mihomo。
- 支持多个包含顶层 `proxies:` 的 Clash/Mihomo YAML 订阅，仅提取 `type: ssr`。
- 每个订阅支持启用、自动更新、保留/排除关键词、名称前后缀。
- 全局每 1 小时更新；每次启动均在使用缓存后立即异步刷新。
- 固定香港、日本、新加坡、台湾、美国五个可编辑关键词地区组。
- 生成独立订阅、全部节点和五个地区的 Surge 外部策略文件。
- 导入和导出可读的 `.msbridge` JSON 配置。
- 第一版采用临时签名，无 Developer ID、公证和应用内更新。
- 仓库未来公开于 `https://github.com/vengence/MihomoSurgeBridge`，采用 MIT License；本地可用后再上传。

## 3. 非目标

- 不支持 Intel、其他操作系统、其他代理客户端、原始 `ssr://` 或 Base64 订阅。
- 不自动操作 Surge 配置，不开发 Surge 配置编辑器。
- 不做节点测速、流量统计、规则分流、内置节点切换或完整代理客户端功能。
- 不做每订阅独立频率、历史缓存、自动回滚、自动升级或多次自动恢复。
- 不做独立守护进程、复杂日志轮换、配置合并或一键卸载。

## 4. 架构

采用轻量模块化单体，一个 SwiftPM 包包含：

1. `MihomoSurgeBridgeCore` library
   - 领域模型
   - YAML 解析和 SSR 节点规范化
   - 过滤、命名、重名处理和地区匹配
   - Mihomo YAML 与 Surge 策略生成
   - `.msbridge` 迁移模型
   - 不访问 UI、网络、磁盘或进程

2. `MihomoSurgeBridge` executable
   - SwiftUI 窗口、菜单栏和应用状态
   - JSON 持久化、缓存和原子文件写入
   - URLSession 订阅下载和一小时调度
   - Mihomo 安装、检测、配置校验和进程管理
   - 输出文件管理、登录启动、日志和诊断

3. `MihomoSurgeBridgeCoreTests` 与 `MihomoSurgeBridgeTests`

唯一第三方运行依赖是 Yams 6.x。应用不启用 App Sandbox，以便读取 Homebrew 二进制和写入用户选择的目录。

全局 UI 状态由 `@MainActor AppModel` 管理。系统能力封装为小型服务，不引入服务容器、事件总线或额外架构框架。

## 5. 数据模型

### 5.1 AppConfiguration

- `schemaVersion: Int`，MVP 固定为 `1`
- `subscriptions: [SubscriptionConfiguration]`
- `regions: [RegionConfiguration]`
- `updateIntervalSeconds: Int`，固定默认 `3600`
- `mihomoSource: MihomoSource`
- `socksPort: UInt16?`
- `outputDirectory: String?`
- `launchAtLogin: Bool`
- `desiredMihomoRunning: Bool`
- `lastScheduledRefreshAt: Date?`

### 5.2 SubscriptionConfiguration

- `id: UUID`
- `name: String`
- `url: URL`
- `isEnabled: Bool`
- `autoUpdate: Bool`
- `includeKeywords: [String]`
- `excludeKeywords: [String]`
- `namePrefix: String`
- `nameSuffix: String`
- `lastSuccessfulUpdate: Date?`
- `lastError: String?`
- `rawNodeCount: Int`
- `filteredNodeCount: Int`

订阅 URL 视为普通本地数据，直接写入 `config.json`，不使用 Keychain。日志仍不记录完整订阅正文、SSR 密码或 SOCKS5 认证信息。

### 5.3 NormalizedSSRNode

保留 Mihomo SSR 所需字段和未知兼容字段。身份由订阅 UUID 与规范化完整节点内容计算 SHA-256；未变化节点的身份不受订阅排列顺序影响。显示名与内部名分离：

- Surge 显示名：前缀 + 原始名 + 后缀，重名追加 `#2`、`#3`。
- Mihomo 内部名：`msb-<identity>`。
- SOCKS 用户名和密码：由 identity 确定性派生，仅绑定 `127.0.0.1`。

若上游修改节点名称或连接参数，该节点被视为新身份。

## 6. 文件布局

```text
~/Library/Application Support/MihomoSurgeBridge/
├── config.json
├── Cache/
│   └── <subscription-id>.yaml
├── Core/
│   └── mihomo
├── Runtime/
│   └── mihomo.yaml
├── Generated/
│   ├── all-ssr.conf
│   ├── subscription-<id>.conf
│   ├── region-hk.conf
│   ├── region-jp.conf
│   ├── region-sg.conf
│   ├── region-tw.conf
│   └── region-us.conf
└── Logs/
    └── app.log
```

自定义输出目录只改变 `Generated` 文件的目标位置。缓存、配置、运行文件、核心和日志始终留在应用数据目录。

## 7. 单端口路由

Mihomo 使用一个 SOCKS listener：

- `listen: 127.0.0.1`
- 固定持久化端口
- `udp: true`
- 每个有效节点一个稳定认证用户

规则使用 `IN-USER` 将认证用户直接映射到对应 `msb-<identity>` SSR 出站。末尾使用拒绝策略，不提供 DIRECT 兜底。Surge 中的每一行使用同一地址和端口，但带不同用户名和密码。

端口首次设置时自动寻找可用端口并让用户确认。后续冲突时停止 Mihomo，只有用户确认后才更换端口并重新生成全部输出。

## 8. 订阅、过滤与命名

- 保留关键词为空表示全部保留；否则命中任意一个即保留。
- 排除关键词优先，命中任意一个即剔除。
- 匹配不区分英文大小写，只支持普通文本。
- 地区匹配使用原始节点名称，而不是带前后缀的显示名。
- 停用订阅保留配置和缓存，但从运行配置和所有输出移除。
- 关闭自动更新仍允许手动更新，缓存继续使用。
- 过滤结果为零时保存规则、保留缓存；从 Mihomo、汇总和地区输出移除节点；独立文件保留为空并写入注释；界面显示警告。

## 9. 更新事务

启动流程：

1. 读取配置和最后成功缓存。
2. 从缓存生成当前运行配置与输出。
3. 清理仅属于本应用的遗留 Mihomo 进程。
4. 按 `desiredMihomoRunning` 恢复 Mihomo。
5. 异步刷新所有开启自动更新的订阅，不阻塞前四步。
6. 运行期间每一小时刷新；睡眠错过周期后，唤醒立即补一次。

单个下载流程：

1. 下载到临时文件，设置合理超时和大小上限。
2. 验证 HTTP、UTF-8、YAML、`proxies:` 和至少一个 SSR 原始节点。
3. 应用过滤和命名，计算有效节点变化。
4. 失败时删除临时文件，保留最后成功缓存和当前输出。

“更新全部”允许每个订阅独立成功或失败。所有成功结果合并后只执行一次生成事务，并且最多受控重启 Mihomo 一次。只有有效节点或凭据变化才重启；时间戳变化不重启。

生成事务先在临时位置生成所有目标，验证 Mihomo 配置成功后逐文件原子替换。若进程在多文件替换中崩溃，下次启动从成功缓存重新生成，不维护历史回滚。

## 10. Surge 输出

策略文件是 Surge `policy-path` 可读取的代理定义列表，不包含 `[Proxy]` 标题。每行格式为：

```text
显示名称 = socks5, 127.0.0.1, <port>, username=<user>, password=<password>, udp-relay=true
```

应用提供独立订阅、全部 SSR 和五个地区的策略组片段，例如：

```ini
[Proxy Group]
全部 SSR = select, policy-path=/absolute/path/all-ssr.conf
```

同时提供完整路径、复制路径、复制通用区块和 Finder 显示。若找到 Surge 官方 CLI，则只校验生成文件，不加载或修改用户配置。

## 11. Mihomo 管理

### Homebrew

- 检测 Apple Silicon 默认路径及 `brew --prefix mihomo` 结果。
- 只使用现有二进制，不执行 brew 安装或升级。
- 二进制消失时停止运行并提示。

### 应用托管

- 从 Mihomo 官方稳定 release 下载 darwin-arm64 归档和官方校验信息。
- 校验后安装到 `Core/mihomo`。
- MVP 只提供安装最新版和重新安装。

进程由应用直接启动，使用应用 Runtime 目录。应用保留 Process 实例、PID、启动时间和配置标记。遗留清理必须同时验证可执行文件、参数中的 Runtime 路径和进程身份，不能按进程名批量结束。

退出应用时先优雅终止 Mihomo，超时后只强制终止已验证的子进程。

## 12. UI

管理窗口采用原生 NavigationSplitView，提供：

- 概览：应用、Mihomo、端口、订阅、输出状态和主要动作。
- 订阅：列表、编辑、过滤预览、立即更新。
- 地区：固定五组关键词和匹配数量。
- 输出：文件状态、复制片段、Finder。
- 设置与诊断：Mihomo 来源、输出目录、登录启动、日志、配置检查和单次连通性测试。

菜单栏提供状态、打开窗口、启动/停止 Mihomo、立即更新和退出。关闭管理窗口不退出应用。

首次启动显示最短设置流程：检测 Homebrew Mihomo或选择托管安装、选择并确认端口、完成。输出目录默认使用应用数据目录。

## 13. 错误处理

- 下载、HTTP、超时、YAML 和节点错误：保留最后成功版本，显示手动重试。
- 输出目录无权限：停止写入，提示重新选择。
- 端口冲突：不静默换端口。
- Mihomo 启动失败：显示来源、版本、路径和脱敏 stderr，允许手动重试。
- 正常退出时停止 Mihomo；Mihomo 手动停止时定时更新继续。
- 所有用户可见错误使用简体中文；日志采用基本脱敏。
- MVP 不自动连续恢复、不维护错误遥测服务。

## 14. 测试与验收

单元测试覆盖：

- YAML 解析与 SSR 节点提取
- 保留/排除过滤、命名和重名
- 五地区匹配
- 稳定身份与 SOCKS 认证映射
- Mihomo 和 Surge 生成内容
- 配置与 `.msbridge` 编解码
- 原子缓存保护与更新变化判定

集成验收覆盖：

- Homebrew/托管 Mihomo 检测
- 配置校验、启动、停止、退出和遗留清理
- 固定端口冲突
- 使用虚构 SSR fixtures 的单端口多认证路由
- Surge 外部策略格式校验（CLI 存在时）
- SwiftPM release 构建、arm64 检查、`.app` 结构和临时签名

MVP 完成标准：在不修改现有 Surge 主配置和脚本原型的前提下，用户可双击启动 `.app`，添加真实 YAML 订阅，生成并复制 Surge 策略组片段，通过至少一个 SSR 节点完成连通性测试，并在退出应用时停止本应用启动的 Mihomo。

## 15. 实施顺序

1. Core 模型、解析、过滤、地区、身份和生成器。
2. 配置、缓存、下载、原子事务和迁移。
3. Mihomo 检测、安装、配置和进程生命周期。
4. SwiftUI 管理窗口、菜单栏和定时更新。
5. 打包脚本、临时签名和本机端到端验收。
6. 应用可替代原型后，另行制定旧原型迁移与 GitHub 发布步骤。

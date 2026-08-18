# MihomoSurgeBridge 方案设计与开发交接

最后更新：2026-08-18
当前版本：0.1.4（构建 5）
项目状态：个人可用 MVP，已完成首次公开发布

## 1. 为什么做这个工具

Surge for Mac 不支持 SSR，但部分现有订阅仍然只有 SSR 节点。Mihomo 本身能连接 SSR，因此本工具让 Mihomo 负责实际出站，再向 Surge 暴露本地 SOCKS5 节点。

目标不是开发新的代理客户端，也不是接管 Surge，而是补上一个很窄的兼容层：

```text
Clash/Mihomo YAML 订阅
        ↓
提取、过滤 SSR 节点
        ↓
生成 Mihomo 配置并启动本地 SOCKS5
        ↓
生成 Surge policy-path 文件和策略组
        ↓
用户手动复制到 Surge
```

MVP 面向个人使用，优先顺序是可用、稳定、容易理解，不为了完整性扩展过多能力。

## 2. 已确认的产品边界

- 应用名称：MihomoSurgeBridge。
- Bundle Identifier：`com.vengence.MihomoSurgeBridge`。
- 平台：Apple Silicon，macOS 13 及以上。
- 形态：原生 SwiftUI 应用，管理窗口加菜单栏常驻图标。
- 更新频率：每 1 小时；启动先用最后成功缓存，同时立即后台刷新。
- 仓库：`vengence/MihomoSurgeBridge`，公开开源，MIT License。
- 订阅 URL 按普通本地配置保存，不使用 Keychain；但日志会隐藏 URL。
- 应用不会读取、写入或重载用户的 Surge 主配置。
- 边界场景优先采用简单明确的处理，不为 MVP 引入复杂恢复机制。

## 3. 当前已经实现

### 3.1 订阅和节点

- 支持多个 HTTP/HTTPS Clash/Mihomo YAML 订阅。
- 只提取顶层 `proxies:` 中 `type: ssr` 的节点。
- 单个订阅可启用或停用、开启每小时自动更新、手动更新。
- 支持保留关键词、排除关键词、名称前缀和后缀。
- 排除优先于保留；匹配忽略英文大小写和重音差异。
- 显示名重复时自动追加 `#2`、`#3`。
- 下载限制为 10 MB，请求超时 30 秒、总资源超时 60 秒。

### 3.2 缓存和更新

- 每个订阅保存一份最后成功的 YAML 缓存。
- 启动先从缓存生成可用配置，再异步刷新开启自动更新的订阅。
- 运行期间每小时刷新。
- 单个订阅失败时保留旧缓存和旧输出，并在界面显示错误。
- 一轮更新完成后统一重新生成；运行配置实际变化时才重启 Mihomo。
- 输出采用原子写入，并清理本应用拥有的过期输出文件。

### 3.3 Mihomo 桥接

- 自动检测 `/opt/homebrew/bin/mihomo` 和 `/usr/local/bin/mihomo`。
- 可从 Mihomo 官方 GitHub Release 安装 darwin-arm64 托管版本，并校验官方 SHA-256。
- 只监听 `127.0.0.1`，不开放局域网访问。
- 所有节点共用一个 SOCKS5 端口。
- 每个节点生成稳定的用户名和密码，通过 Mihomo `IN-USER` 规则映射到对应 SSR 出站。
- 末尾规则为 `MATCH,REJECT`，没有 DIRECT 兜底，避免代理失败时意外直连。
- 启动前先检查生成的 Mihomo YAML。
- 应用退出时停止由应用管理的 Mihomo；关闭管理窗口不会停止。
- 启动时只清理命令行同时匹配 Mihomo 路径和本应用运行配置的遗留进程，不按进程名批量结束。

### 3.4 Surge 输出

- 为每个启用的订阅生成独立 policy-path 文件。
- 生成“全部节点”文件。
- 生成香港、日本、新加坡、台湾、美国五个地区文件，地区关键词可以编辑。
- 生成可直接复制的完整 `[Proxy Group]` 区块。
- 输出节点为带独立认证的本地 SOCKS5 条目。
- 支持复制路径、在 Finder 中显示和重新生成。
- 检测到 Surge CLI 时可以检查生成内容的格式，但不会加载配置。

### 3.5 界面和诊断

- 页面包括概览、订阅、地区、输出、设置与诊断。
- 菜单栏显示 Mihomo 状态，提供打开窗口、启动或停止、立即更新和退出。
- 管理界面使用单例窗口：重复点击菜单栏入口只复用同一个窗口。
- 关闭管理窗口后应用继续运行，只保留菜单栏图标，Dock 图标消失；再次打开时恢复 Dock 图标。
- “检查生成配置”只验证 YAML 能否被当前 Mihomo 解析，不测试网络，也不改变正在运行的 Mihomo 状态。
- “测试代理连通性”使用第一个可用节点，检查本地 SOCKS5、认证路由和外网访问的完整链路。
- 设置页可修改端口和输出目录、安装托管 Mihomo、设置登录启动、导入导出配置、打开日志目录。
- 设置页显示应用版本。
- 应用日志使用 macOS 当前时区的 ISO 8601 时间；Mihomo 日志保持 Mihomo 原格式。

### 3.6 配置迁移

- 支持导入和导出可读的 `.msbridge` JSON 文件。
- 导出文件包含订阅 URL，应视为个人配置，不应提交到公开仓库。
- 迁移文档不携带机器专属的端口和输出路径，导入后使用目标机器的本地设置。

## 4. 技术结构

项目使用 Swift 6、SwiftUI 和 Swift Package Manager，不依赖 Xcode 工程。

### 4.1 模块

`MihomoSurgeBridgeCore` 是无界面的核心库：

- `Models.swift`：配置、订阅、地区和节点模型。
- `SubscriptionParser.swift`：YAML 与 SSR 提取。
- `NodeProcessor.swift`：过滤、命名、稳定身份和认证信息。
- `Generators.swift`：Mihomo YAML 与 Surge 文件生成。
- `Migration.swift`：`.msbridge` 导入导出模型。

`MihomoSurgeBridge` 是 macOS 应用：

- `AppModel.swift`：应用主状态、更新事务和主要用户动作。
- `MihomoManager.swift`：Mihomo 进程校验、启动、停止和遗留清理。
- `SubscriptionClient.swift`：订阅下载。
- `Stores.swift`：配置、缓存、原子文件和应用日志。
- `SystemServices.swift`：端口、Mihomo 定位、进程执行和托管安装。
- `MihomoSurgeBridgeApp.swift`：场景、应用生命周期、Dock 和菜单栏。
- `Views.swift`：全部管理界面。
- `BridgeStatusIcon.swift`：菜单栏状态图标。

唯一第三方 Swift 依赖是 Yams 6.x，用于 YAML 解析和生成。

### 4.2 数据目录

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
│   └── region-<id>.conf
└── Logs/
    ├── app.log
    └── mihomo.log
```

自定义输出目录只改变生成的 Surge 文件位置，其他运行数据仍保留在应用数据目录。

## 5. 关键设计决定及原因

### 5.1 单端口加独立认证

所有 Surge 节点连接同一个本地端口，通过用户名映射到不同 SSR 节点。这样不需要为每个订阅节点分配和管理端口，节点数量变化时也更稳定。

### 5.2 缓存优先启动

启动不等待网络。已有缓存时先恢复输出和 Mihomo，再在后台刷新，避免订阅服务暂时不可用导致整个工具无法使用。

### 5.3 不自动操作 Surge

应用只生成文件和可复制区块。这样不会破坏用户已有 Surge 配置，也不依赖未承诺稳定的自动编辑接口。

### 5.4 配置检查与网络测试分开

“检查生成配置”回答的是格式能否被 Mihomo 读取；“测试代理连通性”回答的是实际代理链路能否访问网络。二者职责不同，配置检查不应改变进程状态。

### 5.5 菜单栏常驻、管理窗口单例

这是后台工具，不需要窗口一直存在。关闭窗口只隐藏 Dock；顶部入口再次打开同一个窗口，防止重复窗口产生不同的临时界面状态。

### 5.6 保留 ISO 8601，但使用本地时区

日志时间需要与用户看到的系统时间一致，同时要保持稳定、可排序的格式，因此使用带数字偏移的本地 ISO 8601，而不是语言相关的日期格式。

## 6. 讨论过并决定 MVP 不做

以下内容不是遗漏，而是已经明确排除：

- Intel Mac、Windows、Linux、iOS 或其他代理客户端。
- 原始 `ssr://`、Base64 订阅或非 YAML 订阅格式。
- 自动读取、合并、修改、重载 Surge 主配置。
- 节点测速排名、流量统计、规则分流和应用内节点切换。
- 成为完整代理客户端或替代 Surge。
- 每个订阅使用独立更新频率；MVP 全局固定一小时。
- 复杂历史缓存、多版本回滚和连续自动恢复。
- 独立守护进程、后台服务或一键卸载器。
- 将订阅 URL 存入 Keychain；当前按普通本地配置处理。
- 首版 Developer ID 正式签名、公证、应用内自动更新。
- 自动管理 Homebrew；应用只使用已安装二进制，或安装自己的托管版本。

除非新的真实使用问题证明必要，后续开发不应默认把这些内容重新加入范围。

## 7. 当前限制和风险

- 应用使用临时签名且未公证，其他机器首次打开可能被 Gatekeeper 拦截。
- 只发布 arm64 构建。
- Surge 配置仍需手动复制；用户修改输出目录后也要同步更新 Surge 中的路径。
- 连通性测试只使用第一个有效节点，适合判断桥接链路，不代表全部节点可用。
- 自动更新按应用运行时间调度，不是系统级定时任务；应用退出后不会更新。
- 日志没有轮换，长期使用可能需要手动清理。
- Mihomo 官方 Release API 或资产命名变化会影响托管安装。
- 没有崩溃遥测或远程诊断，问题排查依赖本地日志和复现步骤。

## 8. 后续可以迭代的方向

这些是候选方向，不是承诺，也不是当前功能。

### 8.1 近期优先考虑

1. 根据真实使用反馈继续补进程生命周期、睡眠唤醒和端口占用的回归测试。
2. 增加简单日志轮换，防止日志无限增长。
3. 改善首次安装、缺少 Mihomo、订阅无 SSR 节点时的引导。
4. 增加可下载的 GitHub Release，并记录校验值。

### 8.2 有明确需求后再做

1. Developer ID 签名和公证。
2. 正式版本更新提示或应用内更新。
3. 支持更多订阅输入格式。
4. 更完整的节点健康检查，但不要把工具扩展成测速平台。
5. Intel 支持；需要重新验证 Mihomo 资产、依赖和打包流程。

## 9. 开发、测试和构建

### 9.1 环境

- macOS 13+
- Apple Silicon
- Swift 6 / Apple Command Line Tools
- 网络首次构建时可访问 Yams 依赖

### 9.2 常用命令

```bash
./scripts/test.sh
./scripts/build-app.sh
```

`test.sh` 覆盖核心解析、过滤、命名、地区、Mihomo/Surge 生成、配置检查状态保持、菜单栏图标、日志时区和单窗口场景。它也会执行完整 debug 构建。

`build-app.sh` 生成：

```text
dist/MihomoSurgeBridge.app
dist/MihomoSurgeBridge.app.zip
```

脚本会构建 arm64 release、组装应用包、临时签名、验证签名、解压 ZIP 再次验证并检查架构。

### 9.3 版本

版本来自 `Resources/Info.plist`：

- `CFBundleShortVersionString`：对外版本。
- `CFBundleVersion`：递增构建号。

任何对外可见的新构建都应同时提升两者，并同步本文档中的当前版本。

## 10. 后续开发交接约定

每轮开发完成后使用 [迭代开发交接模板](迭代开发交接模板.md) 留下记录。至少要写清：为什么改、决定怎么改、实际改了什么、没有做什么、怎样验证、现在还有什么风险。

需要新增设计规格的情况：

- 改变产品行为或用户流程。
- 改变数据模型、配置格式或迁移行为。
- 改变 Mihomo 路由、进程生命周期或 Surge 输出。
- 引入新依赖、新平台或新的发布方式。

小型、局部、可逆的缺陷修复可以不写单独设计规格，但仍要在交接记录中写明根因、修复和测试。

## 11. 新会话接手顺序

新的开发会话或其他 AI 工具开始工作时，按以下顺序读取：

1. `README.md`：理解项目用途和使用方式。
2. 本文档：理解当前事实、边界和历史决定。
3. `docs/迭代开发交接模板.md` 和最新一份迭代交接记录。
4. 与当前需求直接相关的 `docs/superpowers/specs/` 规格。
5. `AppModel.swift`、相关服务和测试，确认文档是否仍与代码一致。

实施前先复现问题并检查 Git 状态。不要推翻已确认决定；如确实需要改变边界，应明确说明新证据、成本和迁移影响，再获得确认。

# MihomoSurgeBridge

Surge 不支持 SSR。MihomoSurgeBridge 是一个 macOS 菜单栏工具，用 Mihomo 接收 SSR 节点，再把它们转换成本地 SOCKS5 节点供 Surge 使用。

它不会读取或修改 Surge 配置。你只需要在应用里添加 Clash/Mihomo YAML 订阅，然后把生成的 `[Proxy Group]` 内容复制到 Surge。

## 要求

- Apple Silicon Mac
- macOS 13 或更高版本
- Surge for Mac
- Homebrew Mihomo，或使用应用内的托管安装

## 使用

1. 在“订阅”中添加包含 `proxies:` 的 Clash/Mihomo YAML 地址。
2. 更新订阅并启动 Mihomo。
3. 在“输出”中复制完整的 `[Proxy Group]` 区块。
4. 粘贴到 Surge 配置，再把需要的组加入你原来的节点选择组。

应用启动时会先使用缓存，并在后台立即更新订阅；之后每小时更新一次。

## 构建

需要 Swift 6 和 Apple Command Line Tools：

```bash
./scripts/test.sh
./scripts/build-app.sh
```

构建结果在 `dist/`。应用目前使用临时签名，没有公证；首次打开时可能需要在 Finder 中右键选择“打开”。

## 数据位置

```text
~/Library/Application Support/MihomoSurgeBridge/
```

这里保存设置、订阅缓存、Mihomo 运行配置、Surge 输出和日志。导出的 `.msbridge` 文件包含订阅 URL，不要随意公开。

## 当前限制

- 只支持 Apple Silicon 和 macOS 13+。
- 只读取 YAML `proxies:` 中的 SSR 节点。
- 不支持原始 `ssr://` 或 Base64 订阅。
- 不做测速、流量统计或应用内节点切换。
- 不会自动修改或重载 Surge 配置。

完整的设计决策、已完成范围和后续方向见 [方案设计与开发交接](docs/MihomoSurgeBridge-方案设计与开发交接.md)。

## License

MIT

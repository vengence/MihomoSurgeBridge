# MihomoSurgeBridge Dock 动态可见性设计

日期：2026-08-18  
状态：已批准

## 目标

管理窗口存在时，MihomoSurgeBridge 保持普通 macOS 应用行为并显示 Dock 图标。用户关闭最后一个管理窗口后，应用继续在菜单栏运行，但 Dock 图标消失。

## 行为

- 首次启动并显示管理窗口：使用 `.regular` 激活策略，Dock 图标可见。
- 关闭最后一个普通管理窗口：切换为 `.accessory`，Dock 图标消失。
- 最小化管理窗口：不视为关闭，Dock 图标继续显示。
- 关闭设置面板、打开文件面板等临时窗口时，如果管理窗口仍存在，不隐藏 Dock 图标。
- 点击菜单栏“打开管理窗口”：先切回 `.regular`，再创建/打开管理窗口并激活应用。
- 关闭窗口不会停止 Mihomo、取消定时更新或退出应用。
- 只有“退出应用”或 `⌘Q` 才执行现有的 Mihomo 停止与应用退出流程。

## 实现

在 `AppDelegate` 中监听 `NSWindow.willCloseNotification`。窗口关闭后的下一次主运行循环中，检查是否仍有可见或最小化的普通标题窗口；如果没有，则调用 `NSApplication.setActivationPolicy(.accessory)`。

菜单栏“打开管理窗口”动作调用统一方法，按以下顺序执行：

1. `NSApplication.setActivationPolicy(.regular)`
2. SwiftUI `openWindow(id: "main")`
3. `NSApplication.activate(ignoringOtherApps: true)`

不设置 `LSUIElement`，因为该配置会永久隐藏 Dock 图标，无法满足窗口打开时恢复 Dock 的要求。

## 验证

- 启动应用后 Dock 图标存在。
- 点击窗口红色关闭按钮后，菜单栏图标保留，Dock 图标消失，应用进程继续运行。
- 菜单栏重新打开窗口后，Dock 图标恢复且窗口位于前台。
- 最小化窗口时 Dock 图标不消失。
- 正常退出仍停止本应用启动的 Mihomo。

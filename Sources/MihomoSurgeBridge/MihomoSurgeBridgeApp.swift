import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
#if DEBUG
        if ProcessInfo.processInfo.environment["MIHOMO_SURGE_BRIDGE_TEST_CLOSE_MAIN_WINDOW"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                NSApplication.shared.windows.first(where: { self.isManagementWindow($0) })?.close()
            }
        }
#endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        MihomoManager.shared.stopSynchronously()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              isManagementWindow(closingWindow) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hideDockIfNoManagementWindowRemains(excluding: closingWindow)
        }
    }

    private func hideDockIfNoManagementWindowRemains(excluding closingWindow: NSWindow) {
        let hasManagementWindow = NSApplication.shared.windows.contains { window in
            guard window !== closingWindow, isManagementWindow(window) else { return false }
            return window.isVisible || window.isMiniaturized
        }
        if !hasManagementWindow {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func isManagementWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }
}

@main
struct MihomoSurgeBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var mihomo = MihomoManager.shared

    var body: some Scene {
        Window("MihomoSurgeBridge", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(mihomo)
                .frame(minWidth: 880, minHeight: 580)
                .task { await model.startupOnce() }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("退出 MihomoSurgeBridge") {
                    Task { await model.quitApplication() }
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(mihomo)
        } label: {
            BridgeStatusIcon(state: mihomo.state.bridgeStatusIconState)
        }
    }
}

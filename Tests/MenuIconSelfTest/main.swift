import AppKit
import SwiftUI

enum MihomoProcessState {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(String)
}

@main
@MainActor
struct MenuIconSelfTest {
    static func main() {
        let cases: [(BridgeStatusIconState, ColorScheme, Bool, String)] = [
            (.running, .light, true, "运行中"),
            (.connecting, .light, true, "连接中"),
            (.failed, .light, false, "异常-浅色"),
            (.failed, .dark, false, "异常-深色"),
            (.paused, .dark, true, "已暂停"),
        ]

        for (state, colorScheme, shouldBeTemplate, label) in cases {
            let image = BridgeStatusIconRenderer.image(for: state, colorScheme: colorScheme)
            guard image.size == NSSize(width: 24, height: 20),
                  image.isTemplate == shouldBeTemplate,
                  nonTransparentPixelCount(in: image) >= 20 else {
                fputs("✗ 菜单栏图标渲染失败：\(label)\n", stderr)
                exit(EXIT_FAILURE)
            }
            print("✓ 菜单栏图标可见：\(label)")
        }
    }

    private static func nonTransparentPixelCount(in image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return 0 }
        var count = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }
}

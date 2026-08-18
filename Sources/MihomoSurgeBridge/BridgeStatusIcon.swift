import AppKit
import SwiftUI

enum BridgeStatusIconState {
    case running
    case connecting
    case failed
    case paused
}

extension MihomoProcessState {
    var bridgeStatusIconState: BridgeStatusIconState {
        switch self {
        case .running: .running
        case .starting: .connecting
        case .failed: .failed
        case .stopped: .paused
        }
    }
}

struct BridgeStatusIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: BridgeStatusIconState

    var body: some View {
        Image(nsImage: BridgeStatusIconRenderer.image(
            for: state,
            colorScheme: colorScheme
        ))
        .renderingMode(state == .failed ? .original : .template)
        .interpolation(.high)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .running: "Mihomo 运行中"
        case .connecting: "Mihomo 正在启动"
        case .failed: "Mihomo 异常"
        case .paused: "Mihomo 已暂停"
        }
    }
}

enum BridgeStatusIconRenderer {
    static func image(for state: BridgeStatusIconState, colorScheme: ColorScheme) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 20), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            let templateColor = NSColor.black
            let visibleColor = colorScheme == .dark ? NSColor.white : NSColor.black
            let normalColor = state == .failed ? visibleColor : templateColor
            let alpha: CGFloat = state == .connecting || state == .paused ? 0.58 : 0.92

            if state == .paused {
                normalColor.withAlphaComponent(0.10).setFill()
                NSBezierPath(ovalIn: NSRect(x: 2, y: 1, width: 20, height: 18)).fill()
            }

            normalColor.withAlphaComponent(alpha).setStroke()
            let links = NSBezierPath()
            links.lineWidth = 1.8
            links.lineCapStyle = .round
            links.move(to: NSPoint(x: 8.2, y: 15))
            links.line(to: NSPoint(x: 15.8, y: 15))
            links.move(to: NSPoint(x: 7.6, y: 13))
            links.line(to: NSPoint(x: 10.6, y: 9))
            links.move(to: NSPoint(x: 16.4, y: 13))
            links.line(to: NSPoint(x: 13.4, y: 9))
            links.stroke()

            fillCircle(center: NSPoint(x: 6, y: 15), radius: 2.5, color: normalColor, alpha: alpha)
            fillCircle(center: NSPoint(x: 18, y: 15), radius: 2.5, color: normalColor, alpha: alpha)
            fillCircle(
                center: NSPoint(x: 12, y: 7),
                radius: 2.6,
                color: state == .failed ? .systemRed : normalColor,
                alpha: state == .failed ? 1 : alpha
            )

            if state == .running {
                fillCircle(center: NSPoint(x: 12, y: 1), radius: 1.35, color: normalColor, alpha: 0.92)
            }
            return true
        }
        image.isTemplate = state != .failed
        return image
    }

    private static func fillCircle(
        center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        alpha: CGFloat
    ) {
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
    }
}

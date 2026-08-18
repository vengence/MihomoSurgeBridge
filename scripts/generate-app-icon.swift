import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("用法：generate-app-icon.swift <1024px 母版路径> <AppIcon.iconset 目录>\n", stderr)
    exit(64)
}

private struct IconSpec {
    let filename: String
    let pixelSize: Int
    let logicalSize: Int
}

private let iconSpecs = [
    IconSpec(filename: "icon_16x16.png", pixelSize: 16, logicalSize: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixelSize: 32, logicalSize: 16),
    IconSpec(filename: "icon_32x32.png", pixelSize: 32, logicalSize: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixelSize: 64, logicalSize: 32),
    IconSpec(filename: "icon_128x128.png", pixelSize: 128, logicalSize: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixelSize: 256, logicalSize: 128),
    IconSpec(filename: "icon_256x256.png", pixelSize: 256, logicalSize: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixelSize: 512, logicalSize: 256),
    IconSpec(filename: "icon_512x512.png", pixelSize: 512, logicalSize: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixelSize: 1024, logicalSize: 512),
]

private func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        deviceRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat { value * scale }

private func circle(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}

private func renderIcon(pixelSize: Int, logicalSize: Int, to outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGenerationError.canvas
    }

    let scale = CGFloat(pixelSize) / 1024
    let compact = logicalSize <= 32
    let simplified = logicalSize <= 128

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill(using: .copy)

    let tileRect = NSRect(
        x: scaled(48, by: scale),
        y: scaled(48, by: scale),
        width: scaled(928, by: scale),
        height: scaled(928, by: scale)
    )
    let tile = NSBezierPath(
        roundedRect: tileRect,
        xRadius: scaled(216, by: scale),
        yRadius: scaled(216, by: scale)
    )
    if compact {
        color(0x0D0F12).setFill()
        tile.fill()
    } else {
        let background = NSGradient(starting: color(0x171A1F), ending: color(0x080A0D))
        background?.draw(in: tile, angle: -90)
    }

    color(0xFFFFFF, alpha: compact ? 0.18 : 0.10).setStroke()
    tile.lineWidth = max(1, scaled(compact ? 8 : 4, by: scale))
    tile.stroke()

    let leftTop = NSPoint(x: scaled(312, by: scale), y: scaled(660, by: scale))
    let rightTop = NSPoint(x: scaled(712, by: scale), y: scaled(660, by: scale))
    let bottom = NSPoint(x: scaled(512, by: scale), y: scaled(340, by: scale))
    let nodeRadius = scaled(compact ? 86 : 78, by: scale)

    if !simplified {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
        shadow.shadowBlurRadius = scaled(22, by: scale)
        shadow.shadowOffset = NSSize(width: 0, height: scaled(-12, by: scale))
        shadow.set()
    }

    let connectorColor = compact ? NSColor.white : color(0xD8DADF)
    connectorColor.setStroke()
    let connectors = NSBezierPath()
    connectors.lineWidth = max(1, scaled(compact ? 52 : 42, by: scale))
    connectors.lineCapStyle = .round
    connectors.move(to: NSPoint(x: scaled(365, by: scale), y: scaled(568, by: scale)))
    connectors.line(to: NSPoint(x: scaled(447, by: scale), y: scaled(443, by: scale)))
    connectors.move(to: NSPoint(x: scaled(659, by: scale), y: scaled(568, by: scale)))
    connectors.line(to: NSPoint(x: scaled(577, by: scale), y: scaled(443, by: scale)))
    connectors.stroke()

    if compact {
        let topBridge = NSBezierPath()
        topBridge.lineWidth = max(1, scaled(50, by: scale))
        topBridge.lineCapStyle = .round
        topBridge.move(to: NSPoint(x: scaled(423, by: scale), y: scaled(660, by: scale)))
        topBridge.line(to: NSPoint(x: scaled(601, by: scale), y: scaled(660, by: scale)))
        topBridge.stroke()
    } else {
        let dotRadius = scaled(simplified ? 20 : 18, by: scale)
        for x in [432.0, 512.0, 592.0] {
            let dot = circle(
                center: NSPoint(x: scaled(x, by: scale), y: scaled(660, by: scale)),
                radius: dotRadius
            )
            connectorColor.setFill()
            dot.fill()
        }
    }

    let nodePaths = [
        circle(center: leftTop, radius: nodeRadius),
        circle(center: rightTop, radius: nodeRadius),
        circle(center: bottom, radius: nodeRadius),
    ]
    if compact || simplified {
        NSColor.white.setFill()
        nodePaths.forEach { $0.fill() }
    } else {
        let silver = NSGradient(starting: NSColor.white, ending: color(0xB7BBC2))
        nodePaths.forEach { silver?.draw(in: $0, angle: -72) }
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.encoding
    }
    try pngData.write(to: outputURL, options: .atomic)
}

private enum IconGenerationError: LocalizedError {
    case canvas
    case encoding

    var errorDescription: String? {
        switch self {
        case .canvas: "无法创建图标画布"
        case .encoding: "无法编码 PNG"
        }
    }
}

let masterURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(
    at: masterURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

try renderIcon(pixelSize: 1024, logicalSize: 512, to: masterURL)
for spec in iconSpecs {
    try renderIcon(
        pixelSize: spec.pixelSize,
        logicalSize: spec.logicalSize,
        to: iconsetURL.appendingPathComponent(spec.filename)
    )
}

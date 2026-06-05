import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let framesURL = root.appendingPathComponent("frames", isDirectory: true)
try? FileManager.default.removeItem(at: framesURL)
try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: true)

let width = 1920
let height = 1080
let fps = 30
let duration = 15
let totalFrames = fps * duration

struct Module {
    let title: String
    let number: String
    let accent: NSColor
    let points: [String]
    let footerLead: String
    let footerRest: String
    let activeStart: CGFloat
    let activeEnd: CGFloat
}

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

let bg = color(0x101416)
let fg = color(0xF2F5EF)
let muted = color(0xAEB8B4)
let surface = color(0x172025, alpha: 0.96)
let surfaceTop = color(0x202B31, alpha: 0.96)

let modules = [
    Module(title: "默认权限", number: "1", accent: color(0x78D08B), points: ["读取项目文件", "修改前确认", "不能联网"], footerLead: "最安全", footerRest: "，也最保守", activeStart: 0.8, activeEnd: 4.7),
    Module(title: "自动审查", number: "2", accent: color(0xE3B65F), points: ["项目内读写", "高风险弹窗", "删除需确认"], footerLead: "推荐", footerRest: "日常使用", activeStart: 5.0, activeEnd: 9.6),
    Module(title: "完全访问", number: "3", accent: color(0xED786A), points: ["代表你操作", "边界最少", "设置会提醒"], footerLead: "不太建议", footerRest: "开启会有提示", activeStart: 10.0, activeEnd: 14.9),
]

func clamp(_ value: CGFloat, _ minValue: CGFloat = 0, _ maxValue: CGFloat = 1) -> CGFloat {
    max(minValue, min(maxValue, value))
}

func smooth(_ a: CGFloat, _ b: CGFloat, _ value: CGFloat) -> CGFloat {
    let p = clamp((value - a) / (b - a))
    return p * p * (3 - 2 * p)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
    a + (b - a) * p
}

func moduleStart(_ index: Int) -> CGFloat {
    [0.45, 4.9, 9.9][index]
}

func moduleX(_ index: Int, t: CGFloat) -> CGFloat {
    let oneCenter: CGFloat = 681.5
    let twoLeft: CGFloat = 389
    let twoRight: CGFloat = 974
    let three = [CGFloat(96), CGFloat(681), CGFloat(1266)]
    let firstShift = smooth(4.25, 5.05, t)
    let secondShift = smooth(9.35, 10.15, t)

    if index == 0 {
        return lerp(lerp(oneCenter, twoLeft, firstShift), three[0], secondShift)
    }
    if index == 1 {
        return lerp(twoRight, three[1], secondShift)
    }
    return three[2]
}

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = fg, weight: NSFont.Weight = .regular, alpha: CGFloat = 1) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font(size, weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: paragraph
    ]
    value.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
}

func fillRect(_ rect: NSRect, _ fill: NSColor, radius: CGFloat = 0) {
    fill.setFill()
    if radius > 0 {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    } else {
        rect.fill()
    }
}

func strokeRect(_ rect: NSRect, _ stroke: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    stroke.setStroke()
    let path = radius > 0 ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) : NSBezierPath(rect: rect)
    path.lineWidth = width
    path.stroke()
}

func drawModule(_ module: Module, index: Int, t: CGFloat) {
    let start = moduleStart(index)
    let show = smooth(start, start + 0.45, t)
    if show <= 0 { return }

    let baseY: CGFloat = 152
    let y = baseY - (1 - show) * 80
    let rect = NSRect(x: moduleX(index, t: t), y: y, width: 557, height: 666)
    let isActive = t >= module.activeStart && t <= module.activeEnd

    NSGraphicsContext.current?.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX, yBy: rect.midY)
    transform.scale(by: 0.96 + show * 0.04)
    transform.translateX(by: -rect.midX, yBy: -rect.midY)
    transform.concat()

    fillRect(rect, surface, radius: 8)
    fillRect(NSRect(x: rect.minX, y: rect.maxY - 120, width: rect.width, height: 120), surfaceTop, radius: 8)
    strokeRect(rect, isActive ? module.accent.withAlphaComponent(0.78) : color(0xF2F5EF, alpha: 0.13), width: isActive ? 4 : 1, radius: 8)
    fillRect(NSRect(x: rect.minX + 28, y: rect.maxY - 32, width: rect.width - 56, height: 4), module.accent.withAlphaComponent(0.46), radius: 2)

    drawText(module.title, x: rect.minX + 38, y: rect.maxY - 93, size: 48, weight: .bold, alpha: show)
    fillRect(NSRect(x: rect.maxX - 114, y: rect.maxY - 109, width: 76, height: 76), module.accent.withAlphaComponent(0.13), radius: 38)
    drawText(module.number, x: rect.maxX - 86, y: rect.maxY - 94, size: 40, color: module.accent, weight: .heavy, alpha: show)

    let pointShow = smooth(start + 0.7, start + 1.2, t)
    for (i, point) in module.points.enumerated() {
        let py = rect.maxY - 206 - CGFloat(i) * 84
        fillRect(NSRect(x: rect.minX + 54, y: py + 12, width: 14, height: 14), module.accent.withAlphaComponent(pointShow), radius: 7)
        drawText(point, x: rect.minX + 96 - (1 - pointShow) * 18, y: py, size: 30, weight: .medium, alpha: pointShow)
    }

    fillRect(NSRect(x: rect.minX + 38, y: rect.minY + 110, width: rect.width - 76, height: 1.5), color(0xF2F5EF, alpha: 0.10))
    drawText(module.footerLead, x: rect.minX + 38, y: rect.minY + 45, size: 28, color: module.accent, weight: .bold, alpha: show)
    let restX = module.footerLead == "不太建议" ? rect.minX + 178 : (module.footerLead == "推荐" ? rect.minX + 126 : rect.minX + 150)
    drawText(module.footerRest, x: restX, y: rect.minY + 47, size: 26, color: muted, weight: .regular, alpha: show)

    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawCursor(t: CGFloat) {
    let visible = smooth(2.7, 3.05, t)
    if visible <= 0 { return }
    var x = moduleX(0, t: t) + 238
    if t >= 5.4 { x = lerp(moduleX(0, t: t) + 238, moduleX(1, t: t) + 238, smooth(5.4, 6.25, t)) }
    if t >= 10.4 { x = lerp(moduleX(1, t: t) + 238, moduleX(2, t: t) + 238, smooth(10.4, 11.2, t)) }
    let y: CGFloat = 198 + sin(t * 5) * 3
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: y + 54))
    path.line(to: NSPoint(x: x, y: y))
    path.line(to: NSPoint(x: x + 16, y: y + 14))
    path.line(to: NSPoint(x: x + 29, y: y - 15))
    path.line(to: NSPoint(x: x + 45, y: y - 8))
    path.line(to: NSPoint(x: x + 31, y: y + 20))
    path.line(to: NSPoint(x: x + 54, y: y + 20))
    path.close()
    fg.withAlphaComponent(visible).setFill()
    path.fill()
    bg.withAlphaComponent(visible).setStroke()
    path.lineWidth = 3
    path.stroke()
}

func drawFrame(_ frame: Int) throws {
    let t = CGFloat(frame) / CGFloat(fps)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    bg.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for x in stride(from: 0, through: width, by: 80) {
        fillRect(NSRect(x: CGFloat(x), y: 0, width: 1, height: CGFloat(height)), color(0xF2F5EF, alpha: 0.035))
    }
    for y in stride(from: 0, through: height, by: 80) {
        fillRect(NSRect(x: 0, y: CGFloat(y), width: CGFloat(width), height: 1), color(0xF2F5EF, alpha: 0.03))
    }

    let top = smooth(0.05, 0.55, t)
    drawText("权限模式", x: 96, y: 944 - (1 - top) * 24, size: 28, color: muted, weight: .medium, alpha: top)
    drawText("从保守到放开，三种选择", x: 96, y: 843 - (1 - top) * 24, size: 64, weight: .heavy, alpha: top)
    strokeRect(NSRect(x: 1595, y: 936, width: 229, height: 58), color(0xF2F5EF, alpha: 0.14), width: 1, radius: 29)
    drawText("项目访问设置", x: 1638, y: 953, size: 24, color: muted, weight: .regular, alpha: top)

    for (index, module) in modules.enumerated() {
        drawModule(module, index: index, t: t)
    }

    let ring = smooth(12.1, 12.45, t) - smooth(14.4, 14.8, t)
    if ring > 0 {
        strokeRect(NSRect(x: 1456 - ring * 16, y: 106 - ring * 16, width: 176 + ring * 32, height: 176 + ring * 32), color(0xED786A, alpha: 0.42 * ring), width: 2, radius: 88 + ring * 16)
    }
    drawCursor(t: t)

    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    let filename = String(format: "frame-%04d.png", frame)
    try png.write(to: framesURL.appendingPathComponent(filename))
}

for frame in 0..<totalFrames {
    autoreleasepool {
        try? drawFrame(frame)
    }
    if frame % 30 == 0 {
        print("Rendered frame \(frame)/\(totalFrames)")
    }
}

print("Frames written to \(framesURL.path)")

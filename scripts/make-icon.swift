// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.12, blue: 0.32, alpha: 1),
                        NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)])!.draw(in: bg, angle: -90)
    // The island
    let w = body.width * 0.62, h = body.width * 0.2
    let pill = NSRect(x: body.midX - w / 2, y: body.maxY - h - body.height * 0.2, width: w, height: h)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2).fill()
    // Album dot + equaliser
    let dot = h * 0.56
    NSGradient(colors: [.systemPink, .systemPurple])!.draw(
        in: NSBezierPath(roundedRect: NSRect(x: pill.minX + h * 0.25, y: pill.midY - dot / 2, width: dot, height: dot),
                         xRadius: dot * 0.25, yRadius: dot * 0.25), angle: -45)
    NSColor.systemGreen.setFill()
    for (i, f) in [0.45, 0.85, 0.6, 0.95].enumerated() {
        let bw = h * 0.09, bh = h * 0.6 * f
        let x = pill.maxX - h * 0.3 - CGFloat(3 - i) * bw * 1.9 - bw
        NSBezierPath(roundedRect: NSRect(x: x, y: pill.midY - bh / 2, width: bw, height: bh), xRadius: bw / 2, yRadius: bw / 2).fill()
    }
    // Progress line
    let lineY = pill.minY - body.height * 0.16
    NSColor(white: 1, alpha: 0.18).setFill()
    NSBezierPath(roundedRect: NSRect(x: pill.minX, y: lineY, width: w, height: h * 0.14), xRadius: h * 0.07, yRadius: h * 0.07).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: pill.minX, y: lineY, width: w * 0.58, height: h * 0.14), xRadius: h * 0.07, yRadius: h * 0.07).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil failed")

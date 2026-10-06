import AppKit
import SwiftUI

/// Minimal two-language localisation: Turkish when the system prefers it, English otherwise.
enum L {
    static let isTurkish = Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    static func t(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }
}

func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

func appIcon(bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path).flattened()
}

/// Icon of an installed browser web app (PWA), e.g. "YouTube Music".
func webAppIcon(named name: String) -> NSImage? {
    let dirs = [
        "~/Applications/Chrome Apps.localized", "~/Applications/Chrome Apps",
        "~/Applications/Brave Browser Apps.localized", "~/Applications/Edge Apps.localized",
        "~/Applications",
    ]
    for dir in dirs {
        let path = (dir as NSString).expandingTildeInPath + "/\(name).app"
        if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path).flattened() }
    }
    return nil
}

extension NSImage {
    /// Plain sRGB bitmap copy — workspace icons carry many reps/colour spaces that render oddly offscreen.
    func flattened(side: CGFloat = 64) -> NSImage {
        let px = Int(side * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return self }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: side, height: side))
        out.addRepresentation(rep)
        return out
    }

    /// Average colour, brightened so it stays readable on the black island.
    var islandTint: Color? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: min(s, 0.75), brightness: max(b, 0.8), alpha: 1))
    }
}

/// Runs AppleScript on one background queue so a slow target app never blocks the UI.
enum ScriptRunner {
    private static let queue = DispatchQueue(label: "NotchIsland.AppleScript", qos: .userInitiated)
    nonisolated(unsafe) private static var cache: [String: NSAppleScript] = [:]

    static func run(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void = { _ in }) {
        queue.async {
            let script: NSAppleScript
            if let cached = cache[source] {
                script = cached
            } else {
                guard let s = NSAppleScript(source: source) else { return }
                cache[source] = s
                script = s
            }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            let output: NSAppleEventDescriptor? = error == nil ? result : nil
            DispatchQueue.main.async { completion(output) }
        }
    }
}

extension NSAppleEventDescriptor {
    private static let listType: DescType = 0x6C69_7374 // 'list'

    func item(_ i: Int) -> NSAppleEventDescriptor? {
        i >= 1 && i <= numberOfItems ? atIndex(i) : nil
    }

    /// Flattens nested AppleScript lists (e.g. `URL of every tab of every window`) into strings.
    var flatStrings: [String] {
        if descriptorType == Self.listType {
            return (0..<numberOfItems).flatMap { atIndex($0 + 1)?.flatStrings ?? [] }
        }
        return [stringValue ?? ""]
    }
}

/// Posts a system media key (play/next/previous) — routed by macOS to whatever is playing.
enum MediaKeys {
    static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    static func post(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | (down ? 0xA00 : 0xB00))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

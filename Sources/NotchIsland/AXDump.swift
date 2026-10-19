import AppKit

/// `NotchIsland --dump-notification-ax <file>`: writes the accessibility tree of on-screen
/// notification banners. Diagnostic only, used to adapt to Notification Center changes across macOS versions.
enum AXDump {
    static func dumpNotificationCenter(to path: String) {
        var out = "trusted=\(AXIsProcessTrusted())\n"
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui") {
            out += "pid=\(app.processIdentifier)\n"
            walk(AXUIElementCreateApplication(app.processIdentifier), depth: 0, into: &out)
        }
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func attr(_ e: AXUIElement, _ name: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        return nil
    }

    private static func walk(_ e: AXUIElement, depth: Int, into out: inout String) {
        guard depth < 14 else { return }
        var actions: CFArray?
        AXUIElementCopyActionNames(e, &actions)
        let fields = [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute, kAXTitleAttribute,
                      kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { k in attr(e, k).map { "\(k.replacingOccurrences(of: "AX", with: ""))=\($0)" } }
        let acts = (actions as? [String])?.joined(separator: ",") ?? ""
        out += String(repeating: "  ", count: depth) + fields.joined(separator: " | ") + (acts.isEmpty ? "" : " | actions=\(acts)") + "\n"
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for c in list { walk(c, depth: depth + 1, into: &out) }
    }
}

/// `NotchIsland --input-lock-selftest <file>`: locks the pointer for a moment, posts a synthetic
/// mouse move and records whether the cursor moved, then unlocks. Diagnostic only.
enum InputLockSelfTest {
    static func run(to path: String) {
        var out = "trusted=\(AXIsProcessTrusted())\n"
        let lock = InputLock()
        func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
        func nudge(from p: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x + 40, y: p.y + 40),
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

        let start = cursor()
        out += "lock(pointer)=\(lock.set(keyboard: false, pointer: true))\n"
        nudge(from: start); spin()
        let whileLocked = cursor()
        out += "moved while locked: \(whileLocked != start) (tap saw \(lock.seenPointerEvents) events)\n"
        lock.release()
        nudge(from: start); spin()
        let afterUnlock = cursor()
        out += "moved after unlock: \(afterUnlock != start)\n"
        out += "lock(keyboard)=\(lock.set(keyboard: true, pointer: false))\n"
        lock.release()
        // Put the cursor back where it was.
        CGWarpMouseCursorPosition(start)
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

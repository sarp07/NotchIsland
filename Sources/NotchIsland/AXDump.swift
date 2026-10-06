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

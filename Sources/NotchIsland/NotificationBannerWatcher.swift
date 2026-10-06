import AppKit

/// Mirrors macOS notification banners (Messages/SMS, Telegram, system alerts…) into the island.
/// Reads the on-screen banner through Accessibility (read-only), and can press the banner's own
/// "Close" action so it doesn't also appear in the corner. Nothing is stored or sent anywhere.
@MainActor
final class NotificationBannerWatcher {
    struct Item {
        let appName: String
        let title: String
        let subtitle: String
        let body: String
    }

    var onNotification: ((Item, NSImage?, URL?) -> Void)?
    var hideSystemBanners = true

    private static let bundleID = "com.apple.notificationcenterui"
    private static let closeNames: Set<String> = ["Close", "Kapat", "Schließen", "Fermer", "Cerrar", "Chiudi", "Fechar",
                                                  "Sluiten", "Закрыть", "閉じる", "关闭", "關閉", "닫기"]
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var seen = Set<String>()
    private var timer: Timer?
    private var scanPending = false
    private var appIndex: [String: URL] = [:]

    func start() {
        guard timer == nil else { return }
        buildAppIndex()
        attach()
        scan(initial: true)
        // Safety net in case an AX notification is missed or Notification Center restarts.
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detach()
        seen.removeAll()
    }

    // MARK: AX observer

    private func attach() {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        pid = app.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<NotificationBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.scheduleScan() }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, element, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        pid = 0
    }

    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.scanPending = false
            self?.scan()
        }
    }

    // MARK: Scanning

    private func scan(initial: Bool = false) {
        guard AXIsProcessTrusted() else { return }
        // Re-attach if Notification Center was restarted.
        let current = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier ?? 0
        if current != pid { detach(); attach() }
        guard pid != 0 else { return }

        var banners: [AXUIElement] = []
        for window in elements(AXUIElementCreateApplication(pid), kAXWindowsAttribute) {
            collectBanners(window, depth: 0, into: &banners)
        }
        let ids = banners.map { string($0, kAXIdentifierAttribute) ?? string($0, kAXDescriptionAttribute) ?? "" }
        let fresh = zip(ids, banners).filter { !$0.0.isEmpty && !seen.contains($0.0) }
        seen = Set(ids)
        // Many "new" banners at once means the user opened Notification Center — that's history, not news.
        guard !initial, !fresh.isEmpty, fresh.count <= 2 else { return }

        for (_, banner) in fresh {
            guard let item = parse(banner) else { continue }
            let url = appURL(named: item.appName)
            onNotification?(item, url.map { NSWorkspace.shared.icon(forFile: $0.path).flattened() }, url)
            if hideSystemBanners { close(banner) }
        }
    }

    private func collectBanners(_ e: AXUIElement, depth: Int, into out: inout [AXUIElement]) {
        guard depth < 10 else { return }
        if string(e, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
            out.append(e)
            return
        }
        for child in elements(e, kAXChildrenAttribute) { collectBanners(child, depth: depth + 1, into: &out) }
    }

    private func parse(_ banner: AXUIElement) -> Item? {
        var texts: [String: String] = [:]
        for child in elements(banner, kAXChildrenAttribute) {
            if let id = string(child, kAXIdentifierAttribute), let v = string(child, kAXValueAttribute) { texts[id] = v }
        }
        // Description is "App, Title, Subtitle, Body" — the app name is the first part.
        let appName = string(banner, kAXDescriptionAttribute)?.components(separatedBy: ", ").first ?? ""
        let title = texts["title"] ?? ""
        guard !title.isEmpty || !(texts["body"] ?? "").isEmpty else { return nil }
        return Item(appName: appName, title: title, subtitle: texts["subtitle"] ?? "", body: texts["body"] ?? "")
    }

    /// Presses the banner's own "Close" action — only for plain banners (no reply/snooze buttons).
    private func close(_ banner: AXUIElement) {
        var names: CFArray?
        guard AXUIElementCopyActionNames(banner, &names) == .success, let actions = names as? [String] else { return }
        let custom = actions.filter { $0.hasPrefix("Name:") }
        guard custom.count <= 3 else { return }
        for action in custom {
            let name = action.components(separatedBy: "\n").first?.dropFirst("Name:".count) ?? ""
            if Self.closeNames.contains(String(name)) {
                AXUIElementPerformAction(banner, action as CFString)
                return
            }
        }
    }

    // MARK: App lookup (display name → bundle URL, e.g. "Mesajlar" → Messages.app)

    private func buildAppIndex() {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    "/System/Library/CoreServices", "~/Applications", "~/Applications/Chrome Apps.localized"]
        let fm = FileManager.default
        for dir in dirs {
            let path = (dir as NSString).expandingTildeInPath
            for name in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where name.hasSuffix(".app") {
                let full = (path as NSString).appendingPathComponent(name)
                let url = URL(fileURLWithPath: full)
                let display = fm.displayName(atPath: full).replacingOccurrences(of: ".app", with: "")
                appIndex[display] = appIndex[display] ?? url
                appIndex[String(name.dropLast(4))] = appIndex[String(name.dropLast(4))] ?? url
            }
        }
    }

    private func appURL(named name: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.bundleURL {
            return running
        }
        return appIndex[name]
    }

    // MARK: AX helpers

    private func value(_ e: AXUIElement, _ attr: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
    }
    private func string(_ e: AXUIElement, _ attr: String) -> String? {
        (value(e, attr) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    private func elements(_ e: AXUIElement, _ attr: String) -> [AXUIElement] {
        (value(e, attr) as? [AXUIElement]) ?? []
    }
}

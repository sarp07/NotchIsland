import AppKit
import ServiceManagement

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hoverToExpand: Bool { didSet { d.set(hoverToExpand, forKey: "hoverToExpand") } }
    @Published var hideMenuBarOnHover: Bool { didSet { d.set(hideMenuBarOnHover, forKey: "hideMenuBarOnHover") } }
    @Published var showMedia: Bool { didSet { d.set(showMedia, forKey: "showMedia") } }
    @Published var showPausedMedia: Bool { didSet { d.set(showPausedMedia, forKey: "showPausedMedia") } }
    @Published var browserMedia: Bool { didSet { d.set(browserMedia, forKey: "browserMedia") } }
    @Published var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD") } }
    @Published var replaceSystemHUD: Bool { didSet { d.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    @Published var showNotifications: Bool { didSet { d.set(showNotifications, forKey: "showNotifications") } }
    @Published var mirrorNotifications: Bool { didSet { d.set(mirrorNotifications, forKey: "mirrorNotifications") } }
    @Published var hideSystemBanners: Bool { didSet { d.set(hideSystemBanners, forKey: "hideSystemBanners") } }
    @Published var showBattery: Bool { didSet { d.set(showBattery, forKey: "showBattery") } }
    @Published var showDevices: Bool { didSet { d.set(showDevices, forKey: "showDevices") } }
    @Published var showOnNonNotch: Bool { didSet { d.set(showOnNonNotch, forKey: "showOnNonNotch") } }
    @Published var alwaysShowPill: Bool { didSet { d.set(alwaysShowPill, forKey: "alwaysShowPill") } }
    @Published var preferBuiltInDisplay: Bool { didSet { d.set(preferBuiltInDisplay, forKey: "preferBuiltInDisplay") } }

    @Published var autoUnlockSeconds: Int { didSet { d.set(autoUnlockSeconds, forKey: "autoUnlockSeconds") } }
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    /// All tools in display order; hidden ones stay in the list so their position is kept.
    @Published var toolOrder: [ToolID] { didSet { d.set(toolOrder.map(\.rawValue), forKey: "toolOrder") } }
    @Published var hiddenTools: Set<ToolID> { didSet { d.set(hiddenTools.map(\.rawValue), forKey: "hiddenTools") } }

    var visibleTools: [ToolID] { toolOrder.filter { !hiddenTools.contains($0) } }

    /// Not persisted, refreshed by AppDelegate's permission watcher.
    @Published var accessibilityGranted = AXIsProcessTrusted()

    private init() {
        d.register(defaults: [
            "hoverToExpand": true, "hideMenuBarOnHover": true, "showMedia": true, "showPausedMedia": true, "browserMedia": true, "showHUD": true,
            "replaceSystemHUD": true, "showNotifications": true, "mirrorNotifications": true, "hideSystemBanners": true, "showBattery": true, "showDevices": true,
            "showOnNonNotch": true, "alwaysShowPill": true, "preferBuiltInDisplay": true,
            "autoUnlockSeconds": 120, "autoCheckUpdates": true,
        ])
        hoverToExpand = d.bool(forKey: "hoverToExpand")
        hideMenuBarOnHover = d.bool(forKey: "hideMenuBarOnHover")
        showMedia = d.bool(forKey: "showMedia")
        showPausedMedia = d.bool(forKey: "showPausedMedia")
        browserMedia = d.bool(forKey: "browserMedia")
        showHUD = d.bool(forKey: "showHUD")
        replaceSystemHUD = d.bool(forKey: "replaceSystemHUD")
        showNotifications = d.bool(forKey: "showNotifications")
        mirrorNotifications = d.bool(forKey: "mirrorNotifications")
        hideSystemBanners = d.bool(forKey: "hideSystemBanners")
        showBattery = d.bool(forKey: "showBattery")
        showDevices = d.bool(forKey: "showDevices")
        showOnNonNotch = d.bool(forKey: "showOnNonNotch")
        alwaysShowPill = d.bool(forKey: "alwaysShowPill")
        preferBuiltInDisplay = d.bool(forKey: "preferBuiltInDisplay")
        autoUnlockSeconds = d.integer(forKey: "autoUnlockSeconds")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        let saved = (d.stringArray(forKey: "toolOrder") ?? []).compactMap(ToolID.init(rawValue:))
        // Keep the saved order and append tools added in newer versions.
        toolOrder = saved + ToolID.defaultOrder.filter { !saved.contains($0) }
        hiddenTools = Set((d.stringArray(forKey: "hiddenTools") ?? []).compactMap(ToolID.init(rawValue:)))
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("NotchIsland: launch at login failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    static func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

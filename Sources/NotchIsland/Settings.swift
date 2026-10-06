import AppKit
import ServiceManagement

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hoverToExpand: Bool { didSet { d.set(hoverToExpand, forKey: "hoverToExpand") } }
    @Published var hideMenuBarOnHover: Bool { didSet { d.set(hideMenuBarOnHover, forKey: "hideMenuBarOnHover") } }
    @Published var showMedia: Bool { didSet { d.set(showMedia, forKey: "showMedia") } }
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

    /// Not persisted — refreshed by AppDelegate's permission watcher.
    @Published var accessibilityGranted = AXIsProcessTrusted()

    private init() {
        d.register(defaults: [
            "hoverToExpand": true, "hideMenuBarOnHover": true, "showMedia": true, "browserMedia": true, "showHUD": true,
            "replaceSystemHUD": true, "showNotifications": true, "mirrorNotifications": true, "hideSystemBanners": true, "showBattery": true, "showDevices": true,
            "showOnNonNotch": true, "alwaysShowPill": true, "preferBuiltInDisplay": true,
        ])
        hoverToExpand = d.bool(forKey: "hoverToExpand")
        hideMenuBarOnHover = d.bool(forKey: "hideMenuBarOnHover")
        showMedia = d.bool(forKey: "showMedia")
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

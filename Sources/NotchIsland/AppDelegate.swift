import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var model: IslandModel!
    private var controller: IslandController!
    private let media = MediaController()
    private let battery = BatteryMonitor()
    private let volume = VolumeController()
    private let brightness = BrightnessController()
    private let keyTap = MediaKeyTap()
    private let badges = DockBadgeWatcher()
    private let banners = NotificationBannerWatcher()
    private var lastMirrored: [String: Date] = [:]
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = IslandGeometry.targetScreen(preferBuiltIn: settings.preferBuiltInDisplay)
        model = IslandModel(geometry: screen.map(IslandGeometry.init(screen:)) ?? .fallback)
        controller = IslandController(model: model, media: media, battery: battery)

        media.$showsCompact
            .sink { [weak self] visible in
                guard let self else { return }
                self.model.mediaVisible = visible && self.settings.showMedia
            }
            .store(in: &cancellables)

        wireServices()
        setupStatusItem()
        applySettings()

        settings.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applySettings() } }
            .store(in: &cancellables)

        // Ask for Accessibility once, on first launch only.
        if !AXIsProcessTrusted() && !UserDefaults.standard.bool(forKey: "didAskAccessibility") {
            UserDefaults.standard.set(true, forKey: "didAskAccessibility")
            openSettings()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.settings.accessibilityGranted { self.settings.accessibilityGranted = trusted }
            }
        }
    }

    private func wireServices() {
        volume.onVolumeChange = { [weak self] value, muted in
            guard let self, self.settings.showHUD else { return }
            self.model.show(.hud(.volume, value, muted: muted), for: 1.6)
        }
        volume.onOutputDeviceChange = { [weak self] name, symbol in
            guard let self, self.settings.showDevices else { return }
            self.model.show(.banner(Banner(symbol: symbol, tint: .blue, title: name,
                                           subtitle: L.t("Ses çıkışı değişti", "Audio output changed"))), for: 3)
        }
        volume.start()

        battery.onEvent = { [weak self] state, event in
            guard let self, self.settings.showBattery else { return }
            let banner: Banner
            switch event {
            case .pluggedIn:
                banner = Banner(symbol: "bolt.fill", tint: .green, title: L.t("Şarj oluyor", "Charging"), subtitle: "%\(state.percent)")
            case .unplugged:
                banner = Banner(symbol: "powerplug.fill", tint: .white, title: L.t("Şarjdan çıkarıldı", "On battery"), subtitle: "%\(state.percent)")
            case .low(let p):
                banner = Banner(symbol: "battery.25percent", tint: .red, title: L.t("Pil azaldı", "Low battery"), subtitle: "%\(p)")
            }
            self.model.show(.banner(banner), for: 3)
        }
        battery.start()

        banners.onNotification = { [weak self] item, icon, url in
            guard let self else { return }
            self.lastMirrored[item.appName] = Date()
            let title = item.title.isEmpty ? item.appName : item.title
            let text = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
            let banner = Banner(icon: icon, symbol: "bell.fill", title: title, subtitle: text.isEmpty ? item.appName : text,
                                action: url.map { u in { NSWorkspace.shared.open(u) } })
            self.model.show(.banner(banner), for: 5)
        }

        badges.onBadge = { [weak self] app, icon, label in
            guard let self else { return }
            // The banner mirror already showed this one.
            if let t = self.lastMirrored[app], Date().timeIntervalSince(t) < 6 { return }
            let count = Int(label)
            let subtitle = count.map { L.t("\($0) yeni bildirim", $0 == 1 ? "1 new notification" : "\($0) new notifications") }
                ?? L.t("Yeni bildirim", "New notification")
            self.model.show(.banner(Banner(icon: icon, symbol: "bell.fill", title: app, subtitle: subtitle)), for: 4)
        }

        keyTap.handler = { [weak self] key, down, fine in
            MainActor.assumeIsolated { self?.handleKey(key, down: down, fine: fine) ?? false }
        }
    }

    private func applySettings() {
        media.configure(enabled: settings.showMedia, browsers: settings.browserMedia)
        model.mediaVisible = media.showsCompact && settings.showMedia
        if settings.showNotifications && settings.accessibilityGranted { badges.start() } else { badges.stop() }
        banners.hideSystemBanners = settings.hideSystemBanners
        if settings.mirrorNotifications && settings.accessibilityGranted { banners.start() } else { banners.stop() }
        if settings.showHUD && settings.replaceSystemHUD && settings.accessibilityGranted { keyTap.start() } else { keyTap.stop() }
        controller.refreshGeometry()
        model.objectWillChange.send()
    }

    /// Returns true when the key was handled (the system HUD is then suppressed).
    private func handleKey(_ key: MediaKeyTap.Key, down: Bool, fine: Bool) -> Bool {
        let step: Float = fine ? 1 / 64 : 1 / 16
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard volume.canControl else { return false }
            guard down else { return true }
            var v = volume.volume
            var muted = volume.isMuted
            switch key {
            case .volumeUp:
                v = min(1, ((v + step) / step).rounded() * step)
                if muted { volume.setMuted(false); muted = false }
            case .volumeDown:
                v = max(0, ((v - step) / step).rounded() * step)
                if v == 0 { volume.setMuted(true); muted = true }
            default:
                muted.toggle()
                volume.setMuted(muted)
            }
            if key != .mute { volume.setVolume(v) }
            model.show(.hud(.volume, v, muted: muted), for: 1.6)
            return true
        case .brightnessUp, .brightnessDown:
            guard brightness.isAvailable, let current = brightness.brightness else { return false }
            guard down else { return true }
            let delta = key == .brightnessUp ? step : -step
            let v = min(1, max(0, ((current + delta) / step).rounded() * step))
            brightness.setBrightness(v)
            model.show(.hud(.brightness, v, muted: false), for: 1.6)
            return true
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "NotchIsland", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Ayarlar…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: L.t("Erişilebilirlik izni ver…", "Grant Accessibility…"),
                         action: #selector(grantAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Çıkış", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func grantAccessibility() { Settings.openAccessibilitySettings() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L.t("NotchIsland Ayarları", "NotchIsland Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

import AppKit
import CoreAudio
import CoreWLAN
import IOBluetooth
import IOKit.pwr_mgt
import SwiftUI

enum ToolID: String, CaseIterable, Identifiable {
    // Raw value kept as "keyboardLock" so saved tool order from 0.3 betas still applies.
    case cleaningLock = "keyboardLock", bluetooth, wifi, micMute, keepAwake, darkMode, screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaningLock: L.t("Temizlik modu", "Cleaning mode")
        case .bluetooth: "Bluetooth"
        case .wifi: "Wi-Fi"
        case .micMute: L.t("Mikrofon", "Microphone")
        case .keepAwake: L.t("Uyanık tut", "Keep awake")
        case .darkMode: L.t("Karanlık mod", "Dark mode")
        case .screenshot: L.t("Ekran görüntüsü", "Screenshot")
        }
    }

    /// Longer description for Settings.
    var detail: String {
        switch self {
        case .cleaningLock: L.t("Klavyeyi, fareyi ve trackpad'i birlikte kilitler. Açmak için ⌃⌥⌘L.",
                                "Locks the keyboard, mouse and trackpad together. Press ⌃⌥⌘L to unlock.")
        case .bluetooth: L.t("Bluetooth'u açar veya kapatır.", "Turns Bluetooth on or off.")
        case .wifi: L.t("Wi-Fi'yi açar veya kapatır.", "Turns Wi-Fi on or off.")
        case .micMute: L.t("Varsayılan mikrofonu sessize alır.", "Mutes the default microphone.")
        case .keepAwake: L.t("Mac'in ve ekranın uykuya geçmesini engeller.", "Keeps the Mac and display awake.")
        case .darkMode: L.t("Açık ve karanlık görünüm arasında geçer.", "Switches between light and dark appearance.")
        case .screenshot: L.t("Ekran görüntüsü aracını açar.", "Opens the screenshot tool.")
        }
    }

    func symbol(active: Bool) -> String {
        switch self {
        case .cleaningLock: active ? "lock.fill" : "keyboard"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .wifi: active ? "wifi" : "wifi.slash"
        case .micMute: active ? "mic.slash.fill" : "mic.fill"
        case .keepAwake: active ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .darkMode: "circle.lefthalf.filled"
        case .screenshot: "camera.viewfinder"
        }
    }

    /// Lock tools use the amber accent when active; everything else uses white.
    var isLock: Bool { self == .cleaningLock }

    static let defaultOrder: [ToolID] = allCases
}

struct LockInfo: Equatable {
    var keyboard: Bool
    var pointer: Bool
    var startedAt: Date
    var endsAt: Date
}

// MARK: - Input lock (event taps)

/// Swallows keyboard and/or pointer events. The unlock shortcut ⌃⌥⌘L always gets through.
/// If the app quits or crashes the taps go away with it, so input can never stay locked.
final class InputLock {
    var onUnlockShortcut: (() -> Void)?
    private(set) var keyboard = false
    private(set) var pointer = false
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var pointerTap: CFMachPort?
    private var pointerSource: CFRunLoopSource?
    /// Where the cursor is held while the pointer is locked.
    private var frozenPoint = CGPoint.zero
    /// Diagnostics: pointer events the tap has seen.
    private(set) var seenPointerEvents = 0

    static let unlockKeyCode: Int64 = 37 // L

    /// Returns false if the event tap could not be created (no Accessibility permission).
    func set(keyboard: Bool, pointer: Bool) -> Bool {
        self.keyboard = keyboard
        self.pointer = pointer
        let any = keyboard || pointer
        // The key tap also runs while only the pointer is locked, to catch the unlock shortcut.
        if any, keyTap == nil {
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
            guard let t = makeTap(.cgSessionEventTap, mask: mask, callback: keyCallback) else { release(); return false }
            keyTap = t.0; keySource = t.1
        }
        if pointer, pointerTap == nil {
            var mask: CGEventMask = 0
            for type in [1, 2, 3, 4, 5, 6, 7, 22, 25, 26, 27, 18, 19, 20, 29, 30, 31, 32, 34] as [UInt64] { mask |= 1 << type }
            // HID level so the cursor itself stops moving, not just the events apps see.
            guard let t = makeTap(.cghidEventTap, mask: mask, callback: pointerCallback)
                    ?? makeTap(.cgSessionEventTap, mask: mask, callback: pointerCallback) else { release(); return false }
            pointerTap = t.0; pointerSource = t.1
        }
        if pointer {
            // The window server moves the cursor before taps see the event, so hold it in place explicitly.
            frozenPoint = CGEvent(source: nil)?.location ?? .zero
            CGAssociateMouseAndMouseCursorPosition(0)
        } else {
            remove(&pointerTap, &pointerSource)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if !any { remove(&keyTap, &keySource) }
        return true
    }

    func release() {
        if pointer { CGAssociateMouseAndMouseCursorPosition(1) }
        keyboard = false
        pointer = false
        remove(&keyTap, &keySource)
        remove(&pointerTap, &pointerSource)
    }

    private func makeTap(_ location: CGEventTapLocation, mask: CGEventMask,
                         callback: CGEventTapCallBack) -> (CFMachPort, CFRunLoopSource?)? {
        guard AXIsProcessTrusted(),
              let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return (tap, source)
    }

    private func remove(_ tap: inout CFMachPort?, _ source: inout CFRunLoopSource?) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handleKey(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == Self.unlockKeyCode {
            let f = event.flags
            if f.contains(.maskControl) && f.contains(.maskAlternate) && f.contains(.maskCommand) {
                DispatchQueue.main.async { [weak self] in self?.onUnlockShortcut?() }
                return nil
            }
        }
        return keyboard ? nil : Unmanaged.passUnretained(event)
    }

    fileprivate func handlePointer(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let pointerTap { CGEvent.tapEnable(tap: pointerTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        seenPointerEvents += 1
        guard pointer else { return Unmanaged.passUnretained(event) }
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            CGWarpMouseCursorPosition(frozenPoint)
        }
        return nil
    }
}

private func keyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputLock>.fromOpaque(refcon).takeUnretainedValue().handleKey(type, event)
}

private func pointerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                             refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputLock>.fromOpaque(refcon).takeUnretainedValue().handlePointer(type, event)
}

// MARK: - Tools controller

@MainActor
final class ToolsController: ObservableObject {
    @Published private(set) var lock: LockInfo?
    @Published private(set) var bluetoothOn: Bool?
    @Published private(set) var wifiOn: Bool?
    @Published private(set) var micMuted = false
    @Published private(set) var keepAwake = false
    @Published private(set) var darkMode = false

    /// Short feedback shown as an island banner (errors, permission hints).
    var onMessage: ((Banner) -> Void)?
    /// Called before a tool opens another app (the island should collapse).
    var onCollapse: (() -> Void)?

    private let input = InputLock()
    private var lockTimer: Timer?
    private var awakeAssertion: IOPMAssertionID = 0

    init() {
        input.onUnlockShortcut = { [weak self] in
            MainActor.assumeIsolated { self?.unlockAll() }
        }
    }

    func isActive(_ tool: ToolID) -> Bool {
        switch tool {
        case .cleaningLock: lock != nil
        case .bluetooth: bluetoothOn == true
        case .wifi: wifiOn == true
        case .micMute: micMuted
        case .keepAwake: keepAwake
        case .darkMode: darkMode
        case .screenshot: false
        }
    }

    /// Re-reads system state; called when the tools page appears.
    func refresh() {
        if let host = IOBluetoothHostController.default() {
            bluetoothOn = host.powerState == kBluetoothHCIPowerStateON
        }
        wifiOn = CWWiFiClient.shared().interface()?.powerOn()
        micMuted = Microphone.isMuted
        darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func perform(_ tool: ToolID) {
        switch tool {
        case .cleaningLock:
            if lock == nil { setLock(keyboard: true, pointer: true) } else { unlockAll() }
        case .bluetooth: toggleBluetooth()
        case .wifi: toggleWiFi()
        case .micMute:
            Microphone.setMuted(!micMuted)
            micMuted = Microphone.isMuted
        case .keepAwake: setKeepAwake(!keepAwake)
        case .darkMode: toggleDarkMode()
        case .screenshot:
            onCollapse?()
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
        }
    }

    // MARK: Locks

    func setLock(keyboard: Bool, pointer: Bool) {
        guard keyboard || pointer else { unlockAll(); return }
        guard AXIsProcessTrusted() else {
            message(symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: L.t("Erişilebilirlik izni gerekli", "Accessibility permission needed"),
                    subtitle: L.t("Ayarlar'dan NotchIsland'a izin ver.", "Allow NotchIsland in Settings."))
            Settings.openAccessibilitySettings()
            return
        }
        guard input.set(keyboard: keyboard, pointer: pointer) else {
            message(symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: L.t("Kilit açılamadı", "Could not lock"), subtitle: L.t("Erişilebilirlik iznini kontrol et.", "Check the Accessibility permission."))
            return
        }
        // Always auto-unlock, so input can never stay locked by mistake.
        let seconds = TimeInterval(max(15, Settings.shared.autoUnlockSeconds))
        let now = Date()
        lock = LockInfo(keyboard: keyboard, pointer: pointer, startedAt: now, endsAt: now.addingTimeInterval(seconds))
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlockAll() }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func unlockAll() {
        guard lock != nil else { return }
        input.release()
        lockTimer?.invalidate()
        lockTimer = nil
        lock = nil
        message(symbol: "lock.open.fill", tint: .green, title: L.t("Kilit açıldı", "Unlocked"),
                subtitle: L.t("Klavye ve fare yeniden çalışıyor.", "Keyboard and pointer work again."))
    }

    // MARK: Bluetooth / Wi-Fi

    private typealias SetBluetoothPower = @convention(c) (Int32) -> Void

    private func toggleBluetooth() {
        let target = !(bluetoothOn ?? false)
        // Turning Bluetooth off with a Bluetooth keyboard or mouse attached would cut off all input.
        if !target, Self.connectedBluetoothInputDevice() != nil {
            message(symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: L.t("Bluetooth kapatılmadı", "Bluetooth left on"),
                    subtitle: L.t("Bağlı bir Bluetooth klavye veya fare var.", "A Bluetooth keyboard or mouse is connected."))
            return
        }
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else {
            openBluetoothSettings()
            return
        }
        unsafeBitCast(sym, to: SetBluetoothPower.self)(target ? 1 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.bluetoothOn != target { self.openBluetoothSettings() }
        }
    }

    private func openBluetoothSettings() {
        onCollapse?()
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
    }

    private static func connectedBluetoothInputDevice() -> IOBluetoothDevice? {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        // Major class 0x05 = peripheral (keyboard, mouse, trackpad).
        return devices.first { $0.isConnected() && $0.deviceClassMajor == 0x05 }
    }

    private func toggleWiFi() {
        guard let iface = CWWiFiClient.shared().interface() else { return }
        do {
            try iface.setPower(!iface.powerOn())
        } catch {
            message(symbol: "wifi.exclamationmark", tint: .orange, title: L.t("Wi-Fi değiştirilemedi", "Could not change Wi-Fi"),
                    subtitle: error.localizedDescription)
        }
        wifiOn = iface.powerOn()
    }

    // MARK: Keep awake / dark mode

    private func setKeepAwake(_ on: Bool) {
        if on {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "NotchIsland: keep awake" as CFString, &awakeAssertion)
            keepAwake = ok == kIOReturnSuccess
        } else {
            if awakeAssertion != 0 { IOPMAssertionRelease(awakeAssertion) }
            awakeAssertion = 0
            keepAwake = false
        }
    }

    private func toggleDarkMode() {
        let script = """
        tell application id "com.apple.systemevents" to tell appearance preferences to set dark mode to not dark mode
        """
        ScriptRunner.run(script) { [weak self] result in
            guard let self else { return }
            if result == nil {
                self.message(symbol: "exclamationmark.triangle.fill", tint: .orange,
                             title: L.t("Görünüm değiştirilemedi", "Could not change appearance"),
                             subtitle: L.t("Otomasyon izninde System Events'e izin ver.", "Allow System Events under Automation."))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
        }
    }

    private func message(symbol: String, tint: Color, title: String, subtitle: String) {
        onMessage?(Banner(symbol: symbol, tint: tint, title: title, subtitle: subtitle))
    }
}

// MARK: - Microphone (default input device)

enum Microphone {
    private static func defaultInput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                                mScope: kAudioDevicePropertyScopeInput,
                                                                mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                                  mScope: kAudioDevicePropertyScopeInput,
                                                                  mElement: kAudioObjectPropertyElementMain)
    nonisolated(unsafe) private static var savedVolume: Float32 = 0.75

    static var isMuted: Bool {
        let dev = defaultInput()
        guard dev != 0 else { return false }
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(dev, &muteAddress), AudioObjectGetPropertyData(dev, &muteAddress, 0, nil, &size, &m) == noErr {
            return m != 0
        }
        var v = Float32(1)
        size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(dev, &volumeAddress, 0, nil, &size, &v) == noErr { return v == 0 }
        return false
    }

    static func setMuted(_ muted: Bool) {
        let dev = defaultInput()
        guard dev != 0 else { return }
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(dev, &muteAddress),
           AudioObjectIsPropertySettable(dev, &muteAddress, &settable) == noErr, settable.boolValue {
            var m = UInt32(muted ? 1 : 0)
            AudioObjectSetPropertyData(dev, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
            return
        }
        // No mute switch on this device: fall back to input volume 0 and restore it later.
        var size = UInt32(MemoryLayout<Float32>.size)
        if muted {
            var current = Float32(0)
            if AudioObjectGetPropertyData(dev, &volumeAddress, 0, nil, &size, &current) == noErr, current > 0 { savedVolume = current }
            var zero = Float32(0)
            AudioObjectSetPropertyData(dev, &volumeAddress, 0, nil, size, &zero)
        } else {
            var v = savedVolume
            AudioObjectSetPropertyData(dev, &volumeAddress, 0, nil, size, &v)
        }
    }
}

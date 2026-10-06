import AppKit
import CoreAudio
import IOKit.ps

// MARK: - Volume (CoreAudio, no permission needed)

@MainActor
final class VolumeController {
    var onVolumeChange: ((Float, Bool) -> Void)?
    var onOutputDeviceChange: ((String, String) -> Void)?

    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'
    private var device = AudioDeviceID(0)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var startedAt = Date()

    func start() {
        startedAt = Date()
        device = Self.defaultOutputDevice()
        attachVolumeListeners()
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    var canControl: Bool { device != 0 && (settable(Self.virtualMainVolume) || settable(kAudioDevicePropertyVolumeScalar, element: 1)) }

    var volume: Float {
        var v = Float32(0)
        if get(Self.virtualMainVolume, &v) { return v }
        if get(kAudioDevicePropertyVolumeScalar, &v, element: 1) { return v }
        return 0
    }

    func setVolume(_ value: Float) {
        var v = Float32(min(max(value, 0), 1))
        if settable(Self.virtualMainVolume) {
            set(Self.virtualMainVolume, &v)
        } else {
            for ch: UInt32 in [1, 2] where settable(kAudioDevicePropertyVolumeScalar, element: ch) {
                set(kAudioDevicePropertyVolumeScalar, &v, element: ch)
            }
        }
    }

    var isMuted: Bool {
        var m = UInt32(0)
        return get(kAudioDevicePropertyMute, &m) && m != 0
    }

    func setMuted(_ muted: Bool) {
        var m = UInt32(muted ? 1 : 0)
        if settable(kAudioDevicePropertyMute) { set(kAudioDevicePropertyMute, &m) }
    }

    // MARK: Listeners

    private func defaultDeviceChanged() {
        detachVolumeListeners()
        device = Self.defaultOutputDevice()
        attachVolumeListeners()
        guard Date().timeIntervalSince(startedAt) > 2, let name = Self.name(of: device) else { return }
        onOutputDeviceChange?(name, Self.symbol(for: device, name: name))
    }

    private func attachVolumeListeners() {
        guard device != 0 else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.startedAt) > 1 else { return }
                self.onVolumeChange?(self.volume, self.isMuted)
            }
        }
        volumeListener = block
        for sel in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var a = Self.address(sel)
            if AudioObjectHasProperty(device, &a) { AudioObjectAddPropertyListenerBlock(device, &a, .main, block) }
        }
    }

    private func detachVolumeListeners() {
        guard device != 0, let block = volumeListener else { return }
        for sel in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var a = Self.address(sel)
            AudioObjectRemovePropertyListenerBlock(device, &a, .main, block)
        }
        volumeListener = nil
    }

    // MARK: CoreAudio helpers

    private static func address(_ sel: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    private func get<T>(_ sel: AudioObjectPropertySelector, _ value: inout T, element: UInt32 = kAudioObjectPropertyElementMain) -> Bool {
        var a = Self.address(sel, element: element)
        guard device != 0, AudioObjectHasProperty(device, &a) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr
    }

    private func set<T>(_ sel: AudioObjectPropertySelector, _ value: inout T, element: UInt32 = kAudioObjectPropertyElementMain) {
        var a = Self.address(sel, element: element)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private func settable(_ sel: AudioObjectPropertySelector, element: UInt32 = kAudioObjectPropertyElementMain) -> Bool {
        var a = Self.address(sel, element: element)
        guard device != 0, AudioObjectHasProperty(device, &a) else { return false }
        var ok = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &a, &ok) == noErr && ok.boolValue
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func symbol(for id: AudioDeviceID, name: String) -> String {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &transport)
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        if transport == kAudioDeviceTransportTypeBuiltIn { return "laptopcomputer" }
        if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort { return "tv" }
        return "hifispeaker"
    }
}

// MARK: - Brightness (built-in display)

final class BrightnessController {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?

    init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return }
        if let g = dlsym(h, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(g, to: GetFn.self) }
        if let s = dlsym(h, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(s, to: SetFn.self) }
    }

    private var builtInDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count = UInt32(0)
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    var isAvailable: Bool { getFn != nil && setFn != nil && builtInDisplay != nil }

    var brightness: Float? {
        guard let getFn, let id = builtInDisplay else { return nil }
        var v = Float(0)
        return getFn(id, &v) == 0 ? v : nil
    }

    func setBrightness(_ value: Float) {
        guard let setFn, let id = builtInDisplay else { return }
        _ = setFn(id, min(max(value, 0), 1))
    }
}

// MARK: - Media key tap (volume / brightness keys → our HUD instead of the system one)

final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    /// (key, isKeyDown, fineStep) → return true to swallow the event.
    var handler: ((Key, Bool, Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: mediaKeyCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        var key: Key?
        var down = false
        if type.rawValue == 14 {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
            let code = (ns.data1 & 0xFFFF_0000) >> 16
            down = (ns.data1 & 0xFF00) >> 8 == 0xA
            switch code {
            case 0: key = .volumeUp
            case 1: key = .volumeDown
            case 7: key = .mute
            case 2: key = .brightnessUp
            case 3: key = .brightnessDown
            default: break
            }
        } else if type == .keyDown || type == .keyUp {
            // Some Apple keyboards send brightness as plain key codes.
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 144: key = .brightnessUp
            case 145: key = .brightnessDown
            default: break
            }
            down = type == .keyDown
        }
        guard let key, let handler else { return pass }
        return handler(key, down, fine) ? nil : pass
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}

// MARK: - Notifications via Dock badges (Accessibility, read-only)

/// macOS has no public API to read other apps' notifications. Dock badge counts
/// (WhatsApp, Mail, Messages, Telegram…) are readable through Accessibility, so we use those.
@MainActor
final class DockBadgeWatcher {
    var onBadge: ((String, NSImage?, String) -> Void)?
    private var timer: Timer?
    private var last: [String: String] = [:]
    private var primed = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = [:]
        primed = false
    }

    private func poll() {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var current: [String: String] = [:]
        var urls: [String: URL] = [:]
        for list in children(app) where string(list, kAXRoleAttribute) == "AXList" {
            for item in children(list) {
                guard let title = string(item, kAXTitleAttribute) else { continue }
                if let label = string(item, "AXStatusLabel"), !label.isEmpty { current[title] = label }
                if let url = value(item, kAXURLAttribute) as? URL { urls[title] = url }
            }
        }
        if primed {
            for (app, label) in current where Self.isIncrease(old: last[app], new: label) {
                onBadge?(app, urls[app].map { NSWorkspace.shared.icon(forFile: $0.path).flattened() }, label)
            }
        }
        last = current
        primed = true
    }

    private static func isIncrease(old: String?, new: String) -> Bool {
        guard let old else { return true }
        if let o = Int(old), let n = Int(new) { return n > o }
        return old != new
    }

    private func value(_ e: AXUIElement, _ attr: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
    }
    private func string(_ e: AXUIElement, _ attr: String) -> String? { value(e, attr) as? String }
    private func children(_ e: AXUIElement) -> [AXUIElement] { (value(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
}

// MARK: - Battery

@MainActor
final class BatteryMonitor: ObservableObject {
    struct State: Equatable {
        var hasBattery = false
        var percent = 100
        var isCharging = false
        var onAC = true
    }
    enum Event { case pluggedIn, unplugged, low(Int) }

    @Published private(set) var state = BatteryMonitor.read()
    var onEvent: ((State, Event) -> Void)?
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.update() }
        }, ctx)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func update() {
        let old = state, new = Self.read()
        state = new
        guard new.hasBattery else { return }
        if new.onAC && !old.onAC { onEvent?(new, .pluggedIn) }
        else if !new.onAC && old.onAC { onEvent?(new, .unplugged) }
        else if !new.onAC, let threshold = [20, 10, 5].first(where: { new.percent <= $0 && old.percent > $0 }) {
            onEvent?(new, .low(threshold))
        }
    }

    static func read() -> State {
        var s = State()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return s }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d["Type"] as? String == "InternalBattery" else { continue }
            s.hasBattery = true
            let cur = d["Current Capacity"] as? Int ?? 0, max = d["Max Capacity"] as? Int ?? 100
            s.percent = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            s.isCharging = d["Is Charging"] as? Bool ?? false
            s.onAC = d["Power Source State"] as? String == "AC Power"
        }
        return s
    }
}

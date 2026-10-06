import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(origin: .zero, size: IslandModel.canvasSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    // Never steal keyboard focus from the app the user is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Full-width black strip over the menu bar, shown while the cursor is on the island so the
/// menu bar (and its full-screen slide-down) stays hidden and only the island is visible.
final class MenuBarShield: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Above the menu bar and status items, below the island panel.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandController {
    let model: IslandModel
    let panel = IslandPanel()
    private let shield = MenuBarShield()
    private var shieldVisible = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var hovering = false
    private var hoverWork: DispatchWorkItem?

    init(model: IslandModel, media: MediaController, battery: BatteryMonitor) {
        self.model = model
        let host = FirstMouseHostingView(rootView: IslandView(model: model, media: media, battery: battery))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: IslandModel.canvasSize)
        panel.contentView = host
        refreshGeometry()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshGeometry() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshGeometry() } })

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.trackMouse() }
            return e
        }) { monitors.append(m) }

        // The island changes size → re-check whether the cursor is still on it.
        model.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.trackMouse() } }
            .store(in: &cancellables)
    }

    func refreshGeometry() {
        let settings = Settings.shared
        guard let screen = IslandGeometry.targetScreen(preferBuiltIn: settings.preferBuiltInDisplay) else { return }
        let g = IslandGeometry(screen: screen)
        if g != model.geometry { model.geometry = g }
        let c = IslandModel.canvasSize
        panel.setFrame(CGRect(x: screen.frame.midX - c.width / 2, y: screen.frame.maxY - c.height,
                              width: c.width, height: c.height), display: true)
        let h = g.notchSize.height
        shield.setFrame(CGRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h),
                        display: false)
        if g.hasNotch || settings.showOnNonNotch {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func setShield(_ visible: Bool) {
        let visible = visible && Settings.shared.hideMenuBarOnHover && panel.isVisible
        guard visible != shieldVisible else { return }
        shieldVisible = visible
        if visible {
            shield.alphaValue = 0
            shield.orderFrontRegardless()
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = visible ? 0.12 : 0.25
            shield.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.shieldVisible else { return }
                self.shield.orderOut(nil)
            }
        })
    }

    private func trackMouse() {
        let inside = model.screenRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        setShield(inside || model.expanded)
        guard inside != hovering else { return }
        hovering = inside
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if inside {
                guard Settings.shared.hoverToExpand, !self.model.expanded else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                self.model.expanded = true
            } else {
                self.model.expanded = false
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.15 : 0.35), execute: work)
    }
}

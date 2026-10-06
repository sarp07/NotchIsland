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

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandController {
    let model: IslandModel
    let panel = IslandPanel()
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
        if g.hasNotch || settings.showOnNonNotch {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func trackMouse() {
        let inside = model.screenRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
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

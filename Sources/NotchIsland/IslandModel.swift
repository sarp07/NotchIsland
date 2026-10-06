import AppKit
import SwiftUI

struct IslandGeometry: Equatable {
    var hasNotch: Bool
    var notchSize: CGSize
    var screenFrame: CGRect

    static let fallback = IslandGeometry(hasNotch: false, notchSize: CGSize(width: 190, height: 30), screenFrame: .zero)

    static func targetScreen(preferBuiltIn: Bool) -> NSScreen? {
        if preferBuiltIn, let builtIn = NSScreen.screens.first(where: \.isBuiltIn) { return builtIn }
        return NSScreen.main ?? NSScreen.screens.first
    }

    init(hasNotch: Bool, notchSize: CGSize, screenFrame: CGRect) {
        self.hasNotch = hasNotch
        self.notchSize = notchSize
        self.screenFrame = screenFrame
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            // No notch: draw a virtual one the height of the menu bar.
            hasNotch = false
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: min(max(menuBar, 28), 32))
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}

enum HUDKind: Equatable { case volume, brightness }

struct Banner: Equatable {
    let id = UUID()
    var icon: NSImage?
    var symbol: String?
    var tint: Color = .white
    var title: String
    var subtitle: String

    static func == (a: Banner, b: Banner) -> Bool { a.id == b.id }
}

enum Transient: Equatable {
    case hud(HUDKind, Float, muted: Bool)
    case banner(Banner)
}

enum DisplayState: Equatable {
    case hidden, idle, music, expanded
    case hud(HUDKind, Float, Bool)
    case banner(Banner)

    /// Identity used for content transitions (value changes inside a HUD don't re-create the view).
    var kind: String {
        switch self {
        case .hidden: "hidden"
        case .idle: "idle"
        case .music: "music"
        case .expanded: "expanded"
        case .hud(let k, _, _): "hud-\(k)"
        case .banner(let b): "banner-\(b.id)"
        }
    }

    var isLarge: Bool {
        switch self {
        case .hud, .banner, .expanded: true
        default: false
        }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    /// Fixed panel size; the island animates inside it.
    static let canvasSize = CGSize(width: 720, height: 260)

    @Published var geometry: IslandGeometry
    @Published var expanded = false
    @Published var mediaVisible = false
    @Published private(set) var transient: Transient?
    private var transientGeneration = 0

    init(geometry: IslandGeometry) {
        self.geometry = geometry
    }

    func show(_ t: Transient, for seconds: TimeInterval) {
        transient = t
        transientGeneration += 1
        let generation = transientGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.transientGeneration == generation else { return }
            self.transient = nil
        }
    }

    var state: DisplayState {
        switch transient {
        case .hud(let k, let v, let m): return .hud(k, v, m)
        case .banner(let b): return .banner(b)
        case nil: break
        }
        if expanded { return .expanded }
        if mediaVisible { return .music }
        return geometry.hasNotch || Settings.shared.alwaysShowPill ? .idle : .hidden
    }

    func size(for s: DisplayState) -> CGSize {
        let n = geometry.notchSize
        switch s {
        case .hidden, .idle: return n
        case .music: return CGSize(width: n.width + 92, height: n.height)
        case .hud: return CGSize(width: max(n.width + 110, 300), height: n.height + 38)
        case .banner: return CGSize(width: max(n.width + 170, 360), height: n.height + 60)
        case .expanded: return CGSize(width: max(n.width + 280, 480), height: n.height + 128)
        }
    }

    func radii(for s: DisplayState) -> (top: CGFloat, bottom: CGFloat) {
        switch s {
        case .hidden, .idle: return geometry.hasNotch ? (0, 10) : (6, 13)
        case .music: return (6, 13)
        case .hud, .banner: return (10, 20)
        case .expanded: return (14, 28)
        }
    }

    /// Island rectangle in screen coordinates (used for hover / click-through).
    func screenRect() -> CGRect {
        let s = size(for: state)
        let f = geometry.screenFrame
        return CGRect(x: f.midX - s.width / 2 - 6, y: f.maxY - s.height - 4, width: s.width + 12, height: s.height + 6)
    }
}

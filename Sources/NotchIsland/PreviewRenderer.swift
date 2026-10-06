import AppKit
import SwiftUI

/// `NotchIsland --render-previews <dir>` renders every island state to PNG (for README / visual checks).
@MainActor
enum PreviewRenderer {
    static func render(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let art = sampleArtwork()
        let track = NowPlaying(source: .spotify, sourceName: "Spotify", title: "Midnight City", artist: "M83",
                               album: "Hurry Up, We're Dreaming", duration: 243, elapsed: 97, isPlaying: true,
                               artwork: art, appIcon: nil, tint: art.islandTint ?? .pink, canSeek: true)
        let battery = BatteryMonitor()

        for hasNotch in [true, false] {
            let geo = IslandGeometry(hasNotch: hasNotch,
                                     notchSize: hasNotch ? CGSize(width: 185, height: 32) : CGSize(width: 190, height: 28),
                                     screenFrame: .zero)
            let suffix = hasNotch ? "notch" : "no-notch"
            let cases: [(String, (IslandModel, MediaController) -> Void)] = [
                ("idle", { _, _ in }),
                ("music", { m, media in media.setPreview(track); m.mediaVisible = true }),
                ("expanded", { m, media in media.setPreview(track); m.expanded = true }),
                ("expanded-empty", { m, _ in m.expanded = true }),
                ("volume", { m, _ in m.show(.hud(.volume, 0.62, muted: false), for: 60) }),
                ("brightness", { m, _ in m.show(.hud(.brightness, 0.8, muted: false), for: 60) }),
                ("notification", { m, _ in
                    m.show(.banner(Banner(icon: appIcon(bundleID: "net.whatsapp.WhatsApp"), symbol: "bell.fill",
                                          title: "WhatsApp", subtitle: L.t("3 yeni bildirim", "3 new notifications"))), for: 60)
                }),
                ("charging", { m, _ in
                    m.show(.banner(Banner(symbol: "bolt.fill", tint: .green, title: L.t("Şarj oluyor", "Charging"), subtitle: "%84")), for: 60)
                }),
                ("airpods", { m, _ in
                    m.show(.banner(Banner(symbol: "airpodspro", tint: .blue, title: "AirPods Pro",
                                          subtitle: L.t("Ses çıkışı değişti", "Audio output changed"))), for: 60)
                }),
            ]
            for (name, setup) in cases {
                let model = IslandModel(geometry: geo)
                let media = MediaController()
                setup(model, media)
                let view = ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.2, blue: 0.45), Color(red: 0.08, green: 0.1, blue: 0.2)],
                                   startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(.white.opacity(0.12)).frame(height: geo.notchSize.height)
                    IslandView(model: model, media: media, battery: battery)
                }
                .frame(width: IslandModel.canvasSize.width, height: IslandModel.canvasSize.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let cg = renderer.cgImage else { continue }
                let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                try? png?.write(to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        print("✓ previews → \(dir)")
    }

    private static func sampleArtwork() -> NSImage {
        let size = NSSize(width: 200, height: 200)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])!.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70)).fill()
            return true
        }
    }
}

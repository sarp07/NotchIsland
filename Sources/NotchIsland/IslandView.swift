import SwiftUI

/// Notch silhouette: concave "ears" at the top corners, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = min(bottomRadius, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let state = model.state
        let size = model.size(for: state)
        let r = model.radii(for: state)

        ZStack(alignment: .top) {
            NotchShape(topRadius: r.top, bottomRadius: r.bottom)
                .fill(Color.black)
                .frame(width: size.width + r.top * 2, height: size.height)
                .shadow(color: .black.opacity(state.isLarge ? 0.5 : 0), radius: 14, y: 6)

            content(for: state)
                .id(state.kind)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                .frame(width: size.width, height: size.height)
                .clipShape(NotchShape(topRadius: 0, bottomRadius: r.bottom))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if case .banner(let b) = state, let action = b.action {
                action()
                model.dismissTransient()
            } else {
                model.expanded.toggle()
            }
        }
        .opacity(state == .hidden ? 0 : 1)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, L.isTurkish ? Locale.current : Locale(identifier: "en_US"))
        .frame(width: IslandModel.canvasSize.width, height: IslandModel.canvasSize.height, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state)
    }

    @ViewBuilder
    private func content(for state: DisplayState) -> some View {
        let notchH = model.geometry.notchSize.height
        switch state {
        case .hidden, .idle:
            Color.clear
        case .music:
            if let np = media.current {
                CompactMusicView(np: np, notchHeight: notchH)
            }
        case .hud(let kind, let value, let muted):
            HUDView(kind: kind, value: value, muted: muted, notchHeight: notchH)
        case .banner(let banner):
            BannerView(banner: banner, notchHeight: notchH)
        case .expanded:
            ExpandedView(media: media, battery: battery.state, notchHeight: notchH,
                         notchWidth: model.geometry.notchSize.width, hasNotch: model.geometry.hasNotch)
        }
    }
}

// MARK: - Compact

struct CompactMusicView: View {
    let np: NowPlaying
    let notchHeight: CGFloat

    var body: some View {
        HStack {
            ArtworkView(np: np, size: notchHeight - 12, radius: 6)
            Spacer()
            EqualizerView(playing: np.isPlaying, color: np.tint)
                .frame(width: 20, height: notchHeight - 18)
        }
        .padding(.horizontal, 11)
        .frame(height: notchHeight)
    }
}

struct EqualizerView: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { i in
                        let level = playing ? 0.3 + 0.7 * abs(sin(t * (2.1 + Double(i) * 0.85) + Double(i) * 1.3)) : 0.22
                        Capsule()
                            .fill(color)
                            .frame(width: 3, height: max(3, geo.size.height * level))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct HUDView: View {
    let kind: HUDKind
    let value: Float
    let muted: Bool
    let notchHeight: CGFloat

    private var symbol: String {
        switch kind {
        case .brightness: return value < 0.3 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value == 0 { return "speaker.slash.fill" }
            return value < 0.33 ? "speaker.wave.1.fill" : value < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                LevelBar(value: muted ? 0 : Double(value), color: kind == .brightness ? .yellow : .white)
                Text("\(Int((muted ? 0 : value) * 100))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
    }
}

struct LevelBar: View {
    let value: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(color).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

struct BannerView: View {
    let banner: Banner
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 12) {
                Group {
                    if let icon = banner.icon {
                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    } else if let symbol = banner.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(banner.tint)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(banner.tint.opacity(0.18)))
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(banner.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var media: MediaController
    let battery: BatteryMonitor.State
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let hasNotch: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top row lives in the "wings" on either side of the camera notch.
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if let np = media.current {
                        if let icon = np.appIcon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                        Text(np.sourceName)
                    } else {
                        Text("NotchIsland")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: hasNotch ? notchWidth : 0)
                Group {
                    if battery.hasBattery { BatteryBadge(state: battery) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(height: notchHeight)

            if let np = media.current {
                NowPlayingPanel(np: np, media: media)
            } else {
                IdlePanel()
            }
        }
    }
}

struct NowPlayingPanel: View {
    let np: NowPlaying
    let media: MediaController

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkView(np: np, size: 84, radius: 14)
                .shadow(color: np.tint.opacity(0.35), radius: 10)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(np.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                if np.duration != nil {
                    ProgressRow(np: np) { media.seek(to: $0) }
                } else {
                    Spacer().frame(height: 4)
                }
                HStack(spacing: 30) {
                    ControlButton(symbol: "backward.fill", size: 16) { media.previous() }
                    ControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.togglePlayPause() }
                    ControlButton(symbol: "forward.fill", size: 16) { media.next() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity)
    }
}

struct ProgressRow: View {
    let np: NowPlaying
    let onSeek: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = np.duration ?? 1
            let pos = dragValue.map { $0 * duration } ?? np.position(at: ctx.date) ?? 0
            HStack(spacing: 8) {
                Text(Self.format(pos))
                GeometryReader { geo in
                    LevelBar(value: duration > 0 ? pos / duration : 0, color: np.tint)
                        .frame(height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(np.canSeek ? DragGesture(minimumDistance: 0)
                            .onChanged { dragValue = min(max($0.location.x / geo.size.width, 0), 1) }
                            .onEnded { _ in
                                if let v = dragValue { onSeek(v * duration) }
                                dragValue = nil
                            } : nil)
                }
                .frame(height: 6)
                Text(Self.format(duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    static func format(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IdlePanel: View {
    var body: some View {
        HStack(alignment: .center) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
                Text(L.t("Şu an bir şey çalmıyor", "Nothing playing"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity)
    }
}

struct BatteryBadge: View {
    let state: BatteryMonitor.State

    private var symbol: String {
        if state.isCharging { return "battery.100percent.bolt" }
        switch state.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(state.percent)%").monospacedDigit()
            Image(systemName: symbol)
                .foregroundStyle(state.isCharging ? .green : state.percent <= 20 ? .red : .white.opacity(0.8))
        }
    }
}

struct ArtworkView: View {
    let np: NowPlaying
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let art = np.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = np.appIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).padding(size * 0.08)
            } else {
                ZStack {
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

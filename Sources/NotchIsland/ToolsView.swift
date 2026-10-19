import SwiftUI

extension Color {
    /// Single accent used for input locks (amber reads as "caution" without alarming red).
    static let islandAmber = Color(red: 1.0, green: 0.74, blue: 0.24)
}

// MARK: - Page switcher (top-left wing of the expanded island)

struct PageSwitcher: View {
    @Binding var page: ExpandedPage

    var body: some View {
        HStack(spacing: 2) {
            tab(.media, symbol: "music.note", label: L.t("Müzik", "Music"))
            tab(.tools, symbol: "square.grid.2x2.fill", label: L.t("Araçlar", "Tools"))
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func tab(_ p: ExpandedPage, symbol: String, label: String) -> some View {
        Button { page = p } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(page == p ? Color.black : Color.white.opacity(0.75))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(page == p ? Color.white : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(page == p ? .isSelected : [])
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: page)
    }
}

// MARK: - Tools grid

struct ToolsPanel: View {
    @ObservedObject var tools: ToolsController
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let items = settings.visibleTools
        VStack(spacing: 10) {
            if items.isEmpty {
                Text(L.t("Ayarlar'dan araç ekleyebilirsin.", "Add tools in Settings."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxHeight: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 8), count: 4), spacing: 10) {
                    ForEach(items) { tool in
                        ToolTile(tool: tool, active: tools.isActive(tool)) { tools.perform(tool) }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(L.t("Kilitliyken açmak için", "To unlock, press"))
                    KeyCaps(keys: ["⌃", "⌥", "⌘", "L"])
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { tools.refresh() }
    }
}

struct ToolTile: View {
    let tool: ToolID
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    private var fill: Color {
        if active { return tool.isLock ? .islandAmber : .white }
        return Color.white.opacity(hovering ? 0.18 : 0.11)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tool.symbol(active: active), variableValue: 1)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(active ? .black : .white)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
                Text(tool.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(active ? 0.95 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
        .onHover { hovering = $0 }
        .help(tool.detail)
        .accessibilityLabel(tool.title)
        .accessibilityValue(active ? L.t("Açık", "On") : L.t("Kapalı", "Off"))
        .animation(.easeOut(duration: 0.18), value: active)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.16)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control Option Command L")
    }
}

// MARK: - Locked state

struct LockedView: View {
    let lock: LockInfo
    let notchHeight: CGFloat
    let onUnlock: () -> Void

    private var title: String {
        switch (lock.keyboard, lock.pointer) {
        case (true, true): L.t("Klavye ve fare kilitli", "Keyboard and pointer locked")
        case (true, false): L.t("Klavye kilitli", "Keyboard locked")
        default: L.t("Fare ve trackpad kilitli", "Mouse and trackpad locked")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.islandAmber)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.islandAmber.opacity(0.18)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(L.t("Açmak için", "Unlock with"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                        KeyCaps(keys: ["⌃", "⌥", "⌘", "L"])
                    }
                }
                Spacer(minLength: 0)
                Countdown(lock: lock)
                if !lock.pointer {
                    Button(action: onUnlock) {
                        Text(L.t("Kilidi aç", "Unlock"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.islandAmber))
                    }
                    .buttonStyle(TileStyle())
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Ring + mm:ss until the automatic unlock.
struct Countdown: View {
    let lock: LockInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let total = max(1, lock.endsAt.timeIntervalSince(lock.startedAt))
            let left = max(0, lock.endsAt.timeIntervalSince(ctx.date))
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: left / total)
                    .stroke(Color.islandAmber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 36, height: 36)
            .accessibilityLabel(L.t("Otomatik açılmaya \(Int(left)) saniye", "\(Int(left)) seconds until it unlocks"))
        }
    }
}

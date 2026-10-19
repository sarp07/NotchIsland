import SwiftUI

struct SettingsView: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section(L.t("Genel", "General")) {
                Toggle(L.t("Üzerine gelince genişlet", "Expand on hover"), isOn: $s.hoverToExpand)
                Toggle(L.t("Ada açıkken menü çubuğunu gizle", "Hide the menu bar while the island is open"), isOn: $s.hideMenuBarOnHover)
                Toggle(L.t("Girişte başlat", "Launch at login"), isOn: Binding(get: { s.launchAtLogin }, set: { s.launchAtLogin = $0 }))
                Toggle(L.t("Dahili ekranı tercih et", "Prefer built-in display"), isOn: $s.preferBuiltInDisplay)
            }
            Section(L.t("Çentiksiz ekranlar", "Screens without a notch")) {
                Toggle(L.t("Sanal çentik göster", "Show a virtual notch"), isOn: $s.showOnNonNotch)
                Toggle(L.t("Boştayken de görünür kalsın", "Keep visible while idle"), isOn: $s.alwaysShowPill)
                    .disabled(!s.showOnNonNotch)
            }
            Section(L.t("Etkinlikler", "Activities")) {
                Toggle(L.t("Şimdi çalan (Spotify, Music)", "Now playing (Spotify, Music)"), isOn: $s.showMedia)
                Toggle(L.t("Tarayıcıdaki YouTube Music / Spotify Web", "YouTube Music / Spotify Web in browser"), isOn: $s.browserMedia)
                    .disabled(!s.showMedia)
                Toggle(L.t("Duraklatılan şarkıyı adada tut", "Keep a paused song in the island"), isOn: $s.showPausedMedia)
                    .disabled(!s.showMedia)
                Toggle(L.t("Ses ve parlaklık göstergesi", "Volume & brightness HUD"), isOn: $s.showHUD)
                Toggle(L.t("Sistem göstergesinin yerine geç", "Replace the system HUD"), isOn: $s.replaceSystemHUD)
                    .disabled(!s.showHUD)
                Toggle(L.t("Sistem bildirimlerini adada göster (SMS, Telegram…)", "Show system notifications in the island (SMS, Telegram…)"), isOn: $s.mirrorNotifications)
                Toggle(L.t("macOS bildirim balonunu gizle", "Hide the macOS notification banner"), isOn: $s.hideSystemBanners)
                    .disabled(!s.mirrorNotifications)
                Text(L.t("Açıksa sağ üstteki balon otomatik kapatılır; bildirim Bildirim Merkezi'nden de kalkar. Yanıt/erteleme düğmeli bildirimlere dokunulmaz.",
                         "When on, the corner banner is closed automatically and also leaves Notification Center. Banners with reply/snooze buttons are left alone."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L.t("Dock rozetleri", "Dock badges"), isOn: $s.showNotifications)
                Toggle(L.t("Pil ve şarj", "Battery & charging"), isOn: $s.showBattery)
                Toggle(L.t("Kulaklık / ses çıkışı", "Headphones / audio output"), isOn: $s.showDevices)
            }
            Section {
                ForEach(s.toolOrder) { tool in
                    HStack(spacing: 10) {
                        Image(systemName: tool.symbol(active: false))
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title)
                            Text(tool.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { move(tool, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(s.toolOrder.first == tool)
                            .accessibilityLabel(L.t("\(tool.title) yukarı taşı", "Move \(tool.title) up"))
                        Button { move(tool, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(s.toolOrder.last == tool)
                            .accessibilityLabel(L.t("\(tool.title) aşağı taşı", "Move \(tool.title) down"))
                        Toggle("", isOn: Binding(
                            get: { !s.hiddenTools.contains(tool) },
                            set: { visible in if visible { s.hiddenTools.remove(tool) } else { s.hiddenTools.insert(tool) } }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel(L.t("\(tool.title) göster", "Show \(tool.title)"))
                    }
                }
                Picker(L.t("Kilit kendiliğinden açılsın", "Unlock automatically after"), selection: $s.autoUnlockSeconds) {
                    Text(L.t("30 saniye", "30 seconds")).tag(30)
                    Text(L.t("1 dakika", "1 minute")).tag(60)
                    Text(L.t("2 dakika", "2 minutes")).tag(120)
                    Text(L.t("5 dakika", "5 minutes")).tag(300)
                }
                Button(L.t("Varsayılan sıraya dön", "Restore default order")) {
                    s.toolOrder = ToolID.defaultOrder
                    s.hiddenTools = []
                }
            } header: {
                Text(L.t("Araçlar", "Tools"))
            } footer: {
                Text(L.t("Klavye veya fare kilitliyken ⌃⌥⌘L ile açabilirsin. Güvenlik için kilit her zaman seçtiğin süre sonunda kendiliğinden açılır.",
                         "While the keyboard or pointer is locked, press ⌃⌥⌘L to unlock. For safety the lock always opens by itself after the time you pick."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Güncellemeler", "Updates")) {
                Toggle(L.t("Güncellemeleri otomatik denetle", "Check for updates automatically"), isOn: $s.autoCheckUpdates)
                HStack {
                    Text(L.t("Sürüm \(Updater.currentVersion)", "Version \(Updater.currentVersion)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("Şimdi denetle", "Check now")) { Updater.shared.check(userInitiated: true) }
                }
            }
            Section(L.t("İzinler", "Permissions")) {
                HStack {
                    Image(systemName: s.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s.accessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("Erişilebilirlik", "Accessibility"))
                        Text(L.t("Ses/parlaklık tuşları, bildirimler ve klavye/fare kilidi için gerekli.",
                                 "Needed for volume/brightness keys, notifications and the keyboard/pointer lock."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !s.accessibilityGranted {
                        Button(L.t("İzin ver", "Grant")) { Settings.openAccessibilitySettings() }
                    }
                }
                Text(L.t("Müzik bilgisi için macOS, Spotify / Music / tarayıcını kontrol etmek üzere ilk kullanımda izin isteyecek.",
                         "For music info macOS will ask once to let NotchIsland control Spotify / Music / your browser."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(L.t("NotchIsland hiçbir yere veri göndermez, analitik veya takip yoktur. Yaptığı ağ istekleri yalnızca Spotify kapak resmi ve GitHub'dan güncelleme kontrolüdür.",
                         "NotchIsland sends no data anywhere: no analytics, no tracking. Its only network requests are Spotify cover art and update checks on GitHub."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 720)
    }

    private func move(_ tool: ToolID, by offset: Int) {
        guard let i = s.toolOrder.firstIndex(of: tool) else { return }
        let j = i + offset
        guard s.toolOrder.indices.contains(j) else { return }
        s.toolOrder.swapAt(i, j)
    }
}

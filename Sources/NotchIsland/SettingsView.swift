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
                Toggle(L.t("Ses ve parlaklık göstergesi", "Volume & brightness HUD"), isOn: $s.showHUD)
                Toggle(L.t("Sistem göstergesinin yerine geç", "Replace the system HUD"), isOn: $s.replaceSystemHUD)
                    .disabled(!s.showHUD)
                Toggle(L.t("Bildirimler (Dock rozetleri)", "Notifications (Dock badges)"), isOn: $s.showNotifications)
                Toggle(L.t("Pil ve şarj", "Battery & charging"), isOn: $s.showBattery)
                Toggle(L.t("Kulaklık / ses çıkışı", "Headphones / audio output"), isOn: $s.showDevices)
            }
            Section(L.t("İzinler", "Permissions")) {
                HStack {
                    Image(systemName: s.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s.accessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("Erişilebilirlik", "Accessibility"))
                        Text(L.t("Ses/parlaklık tuşları ve Dock rozetleri için gerekli.",
                                 "Needed for volume/brightness keys and Dock badges."))
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
                Text(L.t("NotchIsland internete veri göndermez; analitik veya takip yoktur. Tek ağ isteği Spotify kapak resmidir.",
                         "NotchIsland sends no data anywhere — no analytics, no tracking. The only network request is Spotify cover art."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }
}

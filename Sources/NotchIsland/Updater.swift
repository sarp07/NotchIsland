import AppKit
import Combine
import Security
import SwiftUI

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let zipURL: URL?
}

/// Checks GitHub Releases for a newer version and installs it in place.
/// A downloaded build is only installed if it is signed by the same Apple team as the running app.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable { case idle, available, downloading, installing, failed(String) }

    static let shared = Updater()
    static let repo = "sarp07/NotchIsland"
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    @Published private(set) var release: ReleaseInfo?
    @Published private(set) var phase: Phase = .idle
    @Published var panelVisible = false

    var onUpToDate: (() -> Void)?
    var onCheckFailed: (() -> Void)?
    private var timer: Timer?

    func startAutomaticChecks() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if Settings.shared.autoCheckUpdates { self?.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if Settings.shared.autoCheckUpdates { self?.check(userInitiated: false) }
            }
        }
    }

    // MARK: Check

    private struct APIRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    func check(userInitiated: Bool) {
        guard phase != .downloading, phase != .installing,
              let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchIsland/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let api = data.flatMap { try? JSONDecoder().decode(APIRelease.self, from: $0) }
            DispatchQueue.main.async { [weak self] in self?.handle(api, userInitiated: userInitiated) }
        }.resume()
    }

    private func handle(_ api: APIRelease?, userInitiated: Bool) {
        guard let api else {
            if userInitiated { onCheckFailed?() }
            return
        }
        let version = api.tag_name.hasPrefix("v") ? String(api.tag_name.dropFirst()) : api.tag_name
        guard Self.isVersion(version, newerThan: Self.currentVersion) else {
            if userInitiated { onUpToDate?() }
            return
        }
        if !userInitiated, UserDefaults.standard.string(forKey: "skippedVersion") == version { return }
        release = ReleaseInfo(version: version, notes: Self.plainNotes(api.body ?? ""), pageURL: api.html_url,
                              zipURL: api.assets.first { $0.name == "NotchIsland.zip" }?.browser_download_url)
        phase = .available
        panelVisible = true
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Release notes are Markdown; show them as plain lines in the card.
    private static func plainNotes(_ md: String) -> String {
        md.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
            .filter { !$0.hasPrefix("```") && !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "---" }
            .prefix(12)
            .joined(separator: "\n")
    }

    // MARK: Actions

    func later() { panelVisible = false }

    /// Used by PreviewRenderer only.
    func setPreview(_ info: ReleaseInfo) {
        release = info
        phase = .available
    }

    func skipThisVersion() {
        if let v = release?.version { UserDefaults.standard.set(v, forKey: "skippedVersion") }
        panelVisible = false
    }

    func openReleasePage() {
        if let url = release?.pageURL { NSWorkspace.shared.open(url) }
        panelVisible = false
    }

    func install() {
        guard let release, let zipURL = release.zipURL, zipURL.scheme == "https", zipURL.host == "github.com" else {
            openReleasePage(); return
        }
        // Builds made from source are ad-hoc signed: there is no team to verify against, so send them to the page.
        guard let team = Self.ownTeamID(), let bundleID = Bundle.main.bundleIdentifier else {
            openReleasePage(); return
        }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            phase = .failed(L.t("Uygulama klasörüne yazılamıyor. Sayfadan indirip elle kur.", "Can't write to the app folder. Download it from the page instead."))
            return
        }
        phase = .downloading
        Task.detached {
            do {
                let newApp = try await Self.downloadAndVerify(zipURL, version: release.version, bundleID: bundleID, team: team)
                await MainActor.run { self.phase = .installing }
                try Self.replace(target: target, with: newApp)
                await MainActor.run { NSApp.terminate(nil) }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ tr: String, _ en: String) { errorDescription = L.t(tr, en) }
    }

    nonisolated private static func downloadAndVerify(_ url: URL, version: String, bundleID: String, team: String) async throws -> URL {
        let (zip, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("İndirme başarısız oldu.", "The download failed.")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, dir.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = dir.appendingPathComponent("NotchIsland.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError("İndirilen dosya açılamadı.", "Could not unpack the download.")
        }
        // Must be the same app, signed by the same Apple developer team.
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let reqString = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(reqString as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else {
            throw UpdateError("İmza doğrulanamadı, güncelleme kurulmadı.", "Signature check failed, the update was not installed.")
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError("Sürüm numarası uyuşmuyor.", "The version number doesn't match.")
        }
        return app
    }

    /// Swaps the bundle after this process exits, restoring the old one if anything fails, then relaunches.
    nonisolated private static func replace(target: URL, with newApp: URL) throws {
        let script = """
        PID="$1"; TARGET="$2"; NEW="$3"; BACKUP="$2.previous"
        i=0; while kill -0 "$PID" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
        rm -rf "$BACKUP"
        if mv "$TARGET" "$BACKUP" && /usr/bin/ditto "$NEW" "$TARGET"; then rm -rf "$BACKUP"; else rm -rf "$TARGET"; mv "$BACKUP" "$TARGET"; fi
        /usr/bin/open "$TARGET"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "notchisland-update", String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path]
        try p.run()
    }

    /// Team ID of the running app's own signature (nil for ad-hoc builds).
    static func ownTeamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

// MARK: - Always-on-top update card

@MainActor
final class UpdateWindowController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?

    init(updater: Updater) {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 260),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Above regular and full-screen windows, on every Space.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let host = FirstMouseHostingView(rootView: UpdateCard(updater: updater))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        cancellable = updater.$panelVisible.removeDuplicates().sink { [weak self] visible in
            DispatchQueue.main.async { visible ? self?.show() : self?.panel.orderOut(nil) }
        }
    }

    private func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.contentView?.fittingSize ?? CGSize(width: 400, height: 260)
        let f = screen.visibleFrame
        panel.setFrame(CGRect(x: f.maxX - size.width - 12, y: f.maxY - size.height - 12, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }
}

struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("NotchIsland \(updater.release?.version ?? "") hazır", "NotchIsland \(updater.release?.version ?? "") is available"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L.t("Şu an \(Updater.currentVersion) sürümünü kullanıyorsun.", "You're on version \(Updater.currentVersion)."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { updater.later() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(L.t("Sonra hatırlat", "Remind me later"))
                .accessibilityLabel(L.t("Kapat", "Close"))
            }

            if let notes = updater.release?.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 96)
            }

            footer
        }
        .padding(16)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .padding(12)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var footer: some View {
        switch updater.phase {
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updater.phase == .downloading
                     ? L.t("İndiriliyor ve doğrulanıyor…", "Downloading and verifying…")
                     : L.t("Kuruluyor, uygulama yeniden açılacak…", "Installing, the app will reopen…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.islandAmber)
                HStack {
                    Button(L.t("İndirme sayfasını aç", "Open download page")) { updater.openReleasePage() }
                        .buttonStyle(SecondaryCapsule())
                    Spacer()
                    Button(L.t("Tekrar dene", "Try again")) { updater.install() }
                        .buttonStyle(PrimaryCapsule())
                }
            }
        default:
            HStack(spacing: 8) {
                Button(L.t("Bu sürümü atla", "Skip this version")) { updater.skipThisVersion() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("Sonra", "Later")) { updater.later() }
                    .buttonStyle(SecondaryCapsule())
                Button(L.t("Şimdi güncelle", "Update now")) { updater.install() }
                    .buttonStyle(PrimaryCapsule())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct PrimaryCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

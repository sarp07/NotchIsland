import AppKit
import SwiftUI

enum MediaSourceKind: Hashable { case spotify, appleMusic, browser }

struct NowPlaying: Equatable {
    var source: MediaSourceKind
    var sourceName: String
    var title: String
    var artist: String
    var album: String = ""
    var duration: Double?
    var elapsed: Double?
    var elapsedAt = Date()
    var isPlaying: Bool
    var artwork: NSImage?
    var appIcon: NSImage?
    var tint: Color = .white
    var canSeek = false
    var updatedAt = Date()

    func position(at date: Date) -> Double? {
        guard let elapsed else { return nil }
        let p = isPlaying ? elapsed + date.timeIntervalSince(elapsedAt) : elapsed
        return duration.map { min(max(p, 0), $0) } ?? p
    }
}

/// Merges Spotify, Apple Music and browser music tabs into one "now playing" item.
/// Uses only public mechanisms: AppleScript, distributed notifications and media keys.
@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var current: NowPlaying?
    /// Whether the compact (wings) view should show. Stays a few seconds after pausing.
    @Published private(set) var showsCompact = false

    private var states: [MediaSourceKind: NowPlaying] = [:]
    private let spotify = SpotifyProvider()
    private let music = AppleMusicProvider()
    private let browser = BrowserProvider()
    private var hideWork: DispatchWorkItem?

    init() {
        spotify.onUpdate = { [weak self] in self?.update(.spotify, $0) }
        music.onUpdate = { [weak self] in self?.update(.appleMusic, $0) }
        browser.onUpdate = { [weak self] in self?.update(.browser, $0) }
    }

    func configure(enabled: Bool, browsers: Bool) {
        if enabled { spotify.start(); music.start() } else { spotify.stop(); music.stop() }
        if enabled && browsers { browser.start() } else { browser.stop() }
    }

    /// Used by PreviewRenderer only.
    func setPreview(_ np: NowPlaying) {
        current = np
        showsCompact = true
    }

    private func update(_ kind: MediaSourceKind, _ np: NowPlaying?) {
        states[kind] = np
        let all = Array(states.values)
        let next = all.filter(\.isPlaying).max { $0.updatedAt < $1.updatedAt }
            ?? all.max { $0.updatedAt < $1.updatedAt }
        if next != current { current = next }

        hideWork?.cancel()
        if next?.isPlaying == true {
            if !showsCompact { showsCompact = true }
        } else if next == nil {
            showsCompact = false
        } else {
            let work = DispatchWorkItem { [weak self] in self?.showsCompact = false }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }
    }

    func togglePlayPause() {
        guard let c = current else { MediaKeys.post(MediaKeys.play); return }
        switch c.source {
        case .spotify: spotify.command("playpause")
        case .appleMusic: music.command("playpause")
        case .browser: browser.togglePlayPause()
        }
    }

    func next() {
        switch current?.source {
        case .spotify: spotify.command("next track")
        case .appleMusic: music.command("next track")
        default: MediaKeys.post(MediaKeys.next)
        }
    }

    func previous() {
        switch current?.source {
        case .spotify: spotify.command("previous track")
        case .appleMusic: music.command("previous track")
        default: MediaKeys.post(MediaKeys.previous)
        }
    }

    func seek(to seconds: Double) {
        let s = String(format: "%.2f", seconds)
        switch current?.source {
        case .spotify: spotify.command("set player position to \(s)")
        case .appleMusic: music.command("set player position to \(s)")
        default: break
        }
    }
}

// MARK: - Spotify (desktop app)

@MainActor
final class SpotifyProvider {
    static let bundleID = "com.spotify.client"
    var onUpdate: ((NowPlaying?) -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var artworkURL: String?
    private var artwork: NSImage?
    private var tint: Color = .white

    private let stateScript = """
    tell application id "com.spotify.client"
        if player state is stopped then return {"stopped"}
        set t to current track
        return {player state as string, name of t, artist of t, album of t, duration of t, player position, artwork url of t}
    end tell
    """

    func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append((dnc, dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append((wnc, wnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SpotifyProvider.bundleID else { return }
            MainActor.assumeIsolated { self?.onUpdate?(nil) }
        }))
        refresh()
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        onUpdate?(nil)
    }

    func refresh() {
        guard isRunning(Self.bundleID) else { onUpdate?(nil); return }
        ScriptRunner.run(stateScript) { [weak self] d in self?.handle(d) }
    }

    func command(_ c: String) {
        guard isRunning(Self.bundleID) else { return }
        ScriptRunner.run("tell application id \"com.spotify.client\" to \(c)") { [weak self] _ in self?.refresh() }
    }

    private func handle(_ d: NSAppleEventDescriptor?) {
        guard let d, let state = d.item(1)?.stringValue, state != "stopped",
              let title = d.item(2)?.stringValue else { onUpdate?(nil); return }
        let art = d.item(7)?.stringValue
        if art != artworkURL { loadArtwork(art) }
        onUpdate?(NowPlaying(
            source: .spotify, sourceName: "Spotify", title: title,
            artist: d.item(3)?.stringValue ?? "", album: d.item(4)?.stringValue ?? "",
            duration: (d.item(5)?.doubleValue).map { $0 / 1000 }, elapsed: d.item(6)?.doubleValue,
            isPlaying: state == "playing", artwork: artwork, appIcon: appIcon(bundleID: Self.bundleID),
            tint: tint, canSeek: true))
    }

    private func loadArtwork(_ urlString: String?) {
        artworkURL = urlString
        artwork = nil
        tint = .white
        // Only fetch cover art from Spotify's own image CDN over HTTPS.
        guard let urlString, let url = URL(string: urlString), url.scheme == "https",
              url.host?.hasSuffix("scdn.co") == true else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkURL == urlString else { return }
                self.artwork = image
                self.tint = image.islandTint ?? .white
                self.refresh()
            }
        }.resume()
    }
}

// MARK: - Apple Music

@MainActor
final class AppleMusicProvider {
    static let bundleID = "com.apple.Music"
    var onUpdate: ((NowPlaying?) -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var artworkKey: String?
    private var artwork: NSImage?
    private var tint: Color = .white

    private let stateScript = """
    tell application id "com.apple.Music"
        if player state is stopped then return {"stopped"}
        set t to current track
        return {player state as string, name of t, artist of t, album of t, duration of t, player position}
    end tell
    """
    private let artworkScript = """
    tell application id "com.apple.Music"
        try
            return raw data of artwork 1 of current track
        end try
    end tell
    """

    func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append((dnc, dnc.addObserver(forName: .init("com.apple.Music.playerInfo"),
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append((wnc, wnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == AppleMusicProvider.bundleID else { return }
            MainActor.assumeIsolated { self?.onUpdate?(nil) }
        }))
        refresh()
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        onUpdate?(nil)
    }

    func refresh() {
        guard isRunning(Self.bundleID) else { onUpdate?(nil); return }
        ScriptRunner.run(stateScript) { [weak self] d in self?.handle(d) }
    }

    func command(_ c: String) {
        guard isRunning(Self.bundleID) else { return }
        ScriptRunner.run("tell application id \"com.apple.Music\" to \(c)") { [weak self] _ in self?.refresh() }
    }

    private func handle(_ d: NSAppleEventDescriptor?) {
        guard let d, let state = d.item(1)?.stringValue, state != "stopped",
              let title = d.item(2)?.stringValue else { onUpdate?(nil); return }
        let artist = d.item(3)?.stringValue ?? "", album = d.item(4)?.stringValue ?? ""
        let key = "\(title)|\(artist)|\(album)"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            tint = .white
            ScriptRunner.run(artworkScript) { [weak self] a in
                guard let self, self.artworkKey == key, let data = a?.data, let image = NSImage(data: data) else { return }
                self.artwork = image
                self.tint = image.islandTint ?? .white
                self.refresh()
            }
        }
        onUpdate?(NowPlaying(
            source: .appleMusic, sourceName: "Music", title: title, artist: artist, album: album,
            duration: d.item(5)?.doubleValue, elapsed: d.item(6)?.doubleValue,
            isPlaying: state == "playing", artwork: artwork, appIcon: appIcon(bundleID: Self.bundleID),
            tint: tint, canSeek: true))
    }
}

// MARK: - Browser tabs (YouTube Music, Spotify Web) — reads only tab URL + title

@MainActor
final class BrowserProvider {
    private struct Browser { let bundleID: String; let titleProperty: String }
    private static let browsers = [
        Browser(bundleID: "com.google.Chrome", titleProperty: "title"),
        Browser(bundleID: "com.brave.Browser", titleProperty: "title"),
        Browser(bundleID: "com.microsoft.edgemac", titleProperty: "title"),
        Browser(bundleID: "company.thebrowser.Browser", titleProperty: "title"),
        Browser(bundleID: "com.vivaldi.Vivaldi", titleProperty: "title"),
        Browser(bundleID: "com.apple.Safari", titleProperty: "name"),
    ]

    var onUpdate: ((NowPlaying?) -> Void)?
    private var timer: Timer?
    private var lastKey: String?
    private var playing = true
    private var lastTrack: NowPlaying?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastKey = nil
        onUpdate?(nil)
    }

    func togglePlayPause() {
        MediaKeys.post(MediaKeys.play)
        playing.toggle()
        if var t = lastTrack {
            t.isPlaying = playing
            t.updatedAt = Date()
            lastTrack = t
            onUpdate?(t)
        }
    }

    private func poll() {
        let running = Self.browsers.filter { isRunning($0.bundleID) }
        guard !running.isEmpty else { publish(nil); return }
        var pending = running.count
        var found: NowPlaying?
        for b in running {
            let script = """
            tell application id "\(b.bundleID)"
                return {URL of every tab of every window, \(b.titleProperty) of every tab of every window}
            end tell
            """
            ScriptRunner.run(script) { [weak self] d in
                guard let self else { return }
                if found == nil, let d { found = self.match(d, browserID: b.bundleID) }
                pending -= 1
                if pending == 0 { self.publish(found) }
            }
        }
    }

    private func match(_ d: NSAppleEventDescriptor, browserID: String) -> NowPlaying? {
        let urls = d.item(1)?.flatStrings ?? [], titles = d.item(2)?.flatStrings ?? []
        for (url, title) in zip(urls, titles) {
            if url.contains("music.youtube.com"), let np = Self.parseYouTubeMusic(title) {
                var t = np
                t.appIcon = webAppIcon(named: "YouTube Music") ?? appIcon(bundleID: browserID)
                return t
            }
            if url.contains("open.spotify.com"), let np = Self.parseSpotifyWeb(title) {
                var t = np
                t.appIcon = appIcon(bundleID: SpotifyProvider.bundleID) ?? appIcon(bundleID: browserID)
                return t
            }
        }
        return nil
    }

    /// "Song | YouTube Music" (also "-" / "–" variants); plain "YouTube Music" means nothing loaded.
    static func parseYouTubeMusic(_ title: String) -> NowPlaying? {
        var t = title.trimmingCharacters(in: .whitespaces)
        for suffix in [" | YouTube Music", " - YouTube Music", " – YouTube Music"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count))
        }
        guard !t.isEmpty, t != "YouTube Music" else { return nil }
        let parts = t.components(separatedBy: " • ")
        return NowPlaying(source: .browser, sourceName: "YouTube Music", title: parts[0],
                          artist: parts.count > 1 ? parts[1] : "YouTube Music", isPlaying: true)
    }

    /// Spotify Web shows "Song • Artist" while playing, "Spotify – …" otherwise.
    static func parseSpotifyWeb(_ title: String) -> NowPlaying? {
        let parts = title.components(separatedBy: " • ")
        guard parts.count >= 2, !title.hasPrefix("Spotify") else { return nil }
        return NowPlaying(source: .browser, sourceName: "Spotify Web", title: parts[0],
                          artist: parts[1...].joined(separator: " • "), isPlaying: true)
    }

    private func publish(_ np: NowPlaying?) {
        guard var np else {
            if lastKey != nil { lastKey = nil; lastTrack = nil; onUpdate?(nil) }
            return
        }
        let key = "\(np.sourceName)|\(np.title)|\(np.artist)"
        guard key != lastKey else { return }
        // A new title means a new track started playing.
        lastKey = key
        playing = true
        np.isPlaying = true
        lastTrack = np
        onUpdate?(np)
    }
}

import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-previews") {
        _ = NSApplication.shared
        PreviewRenderer.render(to: i + 1 < args.count ? args[i + 1] : "previews")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

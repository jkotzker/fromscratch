import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    // NSApplication.delegate is weak; nothing else would keep the delegate alive while the app runs.
    withExtendedLifetime(delegate) { app.run() }
}

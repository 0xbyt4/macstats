import AppKit

// Plain AppKit entry point. The app has no windows, only a menu bar item,
// so it does not use the SwiftUI App lifecycle.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

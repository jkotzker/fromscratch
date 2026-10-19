import AppKit
import SwiftUI

/// The Settings window (⌘,): one fixed-size pane, reused and brought forward on every open.
@MainActor
final class SettingsWindowController: NSWindowController {
    let viewModel: SettingsModel
    private var hasBeenShown = false

    init(viewModel: SettingsModel) {
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: SettingsView(model: viewModel))
        // The window takes the form's size, and follows it if a long scheme name widens the picker.
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        // No resizing and no minimize or zoom: the pane has one size and is quick to reopen.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // Opens over the editor when it is in full screen instead of switching Spaces.
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        guard let window else { return }
        // Centred the first time; after that it reopens where it was left.
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

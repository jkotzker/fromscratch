import AppKit
import FromScratchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var editor: EditorWindowController?
    private var sigtermSource: DispatchSourceSignal?
    /// Set by "Quit Anyway" after a failed save, so the next terminate goes through.
    private var quitDespiteUnsavedText = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let directory = DataLocation.directory(
            environment: ProcessInfo.processInfo.environment,
            isDebug: isDebug,
            home: FileManager.default.homeDirectoryForCurrentUser)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Could not create the data folder \(directory.path): \(error)")
        }

        Fonts.registerBundled()
        NSApp.mainMenu = Self.makeMainMenu()

        let model = AppModel(dataDirectory: directory)
        let editor = EditorWindowController(model: model)
        self.model = model
        self.editor = editor
        installTerminationSignalHandler()

        editor.show()
        NSApp.activate()

        #if DEBUG
        NSLog("FROMSCRATCH_DEBUG launched; data folder %@; font %@; TextKit 2: %@",
              directory.path, editor.textView.font?.fontName ?? "none",
              editor.textView.textLayoutManager != nil ? "yes" : "no")
        runDebugHooks()
        #endif
    }

    // Closing the window quits, as in v2 (window-all-closed calls app.quit()).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // ⌘Q, the Dock's Quit, logout and restart all arrive here. ContentStore disables sudden
    // termination while text is pending, so the system has to ask rather than kill the process.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        flushAll()
        guard let model, model.content.hasPendingWrite, !quitDespiteUnsavedText else { return .terminateNow }
        // The write failed and the text exists only in memory: quitting now would lose it.
        logUnsavedText(model)
        // A run-loop block, not a main-queue block: the alert's modal loop would otherwise run
        // inside a main-queue block and stall the queue, including the SIGTERM source.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.showSaveFailedAlert() }
        }
        return .terminateCancel
    }

    private func showSaveFailedAlert() {
        guard let model else { return }
        let path = model.dataDirectory.appendingPathComponent(ContentStore.fileName).path
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Your note could not be saved."
        alert.informativeText = """
            FromScratch could not write \(path).

            \(model.content.lastWriteError?.localizedDescription ?? "Unknown error.")

            If you quit anyway, changes since the last save will be lost.
            """
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Quit Anyway")
        if alert.runModal() == .alertSecondButtonReturn {
            quitDespiteUnsavedText = true
        }
        // Try Again re-runs applicationShouldTerminate, which flushes and checks again.
        NSApp.terminate(nil)
    }

    private func logUnsavedText(_ model: AppModel) {
        let path = model.dataDirectory.appendingPathComponent(ContentStore.fileName).path
        NSLog("FROMSCRATCH UNSAVED TEXT: could not write %@: %@", path,
              model.content.lastWriteError.map { String(describing: $0) } ?? "unknown error")
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushAll()
    }

    /// Content first: it is the user's text, and settings can always be rebuilt.
    private func flushAll() {
        editor?.storeWindowState()
        model?.content.flush()
        model?.settings.flush()
    }

    // `kill`, launchd and shutdown scripts send SIGTERM, which bypasses applicationShouldTerminate.
    // Ignoring the default action and handling it on the main queue lets both stores flush first.
    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { exit(0) }
                self.flushAll()
                // No UI is possible here; say loudly that text was lost and exit non-zero.
                if let model = self.model, model.content.hasPendingWrite {
                    self.logUnsavedText(model)
                    exit(EXIT_FAILURE)
                }
                exit(0)
            }
        }
        source.resume()
        sigtermSource = source
    }

    /// The minimum to make the app usable and let ⌘Q and ⌘W reach the quit path. The full menu
    /// bar is Task 9.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "FromScratch")
        app.addItem(withTitle: "Hide FromScratch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit FromScratch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        for submenu in [app, file, edit] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    #if DEBUG
    /// Launch checks without GUI access. `FROMSCRATCH_DEBUG_APPEND=<text>` appends that text 0.5 s
    /// after launch through the typing path. `FROMSCRATCH_DEBUG_THEN=terminate` then sends the
    /// action ⌘Q sends (`terminate:`), `=close` sends the window the action ⌘W sends (`performClose:`), and `=zoom-close`
    /// zooms the window, waits 1 s, then closes it.
    private func runDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["FROMSCRATCH_DEBUG_APPEND"], let editor else { return }
        let then = env["FROMSCRATCH_DEBUG_THEN"]
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            editor.debugAppend(text)
            switch then {
            case "terminate":
                NSApp.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: nil)
            case "zoom-close":
                // Zoom, let the zoom settle, then close: isMaximized must survive the quit flush.
                editor.window?.zoom(nil)
                try? await Task.sleep(for: .seconds(1))
                NSLog("FROMSCRATCH_DEBUG zoomed: %@", editor.window?.isZoomed == true ? "yes" : "no")
                editor.window?.performClose(nil)
            case "close":
                // Sent to the window itself: a process launched from a shell is not always made
                // active, and with no key window a nil-targeted performClose: reaches nothing.
                NSLog("FROMSCRATCH_DEBUG closing; window is key: %@", editor.window?.isKeyWindow == true ? "yes" : "no")
                editor.window?.performClose(nil)
            default:
                break
            }
        }
    }
    #endif
}

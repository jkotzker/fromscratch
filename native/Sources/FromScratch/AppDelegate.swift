import AppKit
import FromScratchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var model: AppModel?
    private var editor: EditorWindowController?
    private(set) var schemeController: SchemeController?
    private(set) var fontController: FontController?
    private(set) var settingsWindow: SettingsWindowController?
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

        let model = AppModel(dataDirectory: directory)
        attach(model: model)
        NSApp.mainMenu = MainMenu.build(from: Commands.defaults, schemeMenuDelegate: schemeController)
        let editor = EditorWindowController(model: model)
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

    /// The controllers behind the View menu's scheme and font commands and the Settings window.
    /// The font controller becomes the font manager's target so font panel choices are stored.
    func attach(model: AppModel) {
        self.model = model
        let schemes = SchemeController(model: model)
        let fonts = FontController(model: model)
        schemeController = schemes
        fontController = fonts
        NSFontManager.shared.target = fonts
        settingsWindow = SettingsWindowController(
            viewModel: SettingsModel(app: model, schemes: schemes, fonts: fonts))
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

    // MARK: App menu commands (src/main/menu.js)

    @objc func openWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(Commands.websiteURL)
    }

    @objc func openSupport(_ sender: Any?) {
        NSWorkspace.shared.open(Commands.repositoryURL.appendingPathComponent("issues"))
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSWorkspace.shared.open(Commands.repositoryURL.appendingPathComponent("releases"))
    }

    // MARK: Settings and View menu commands

    // Here rather than on the editor so they also work while Settings or the font panel is key.
    @objc func showSettings(_ sender: Any?) {
        settingsWindow?.show()
    }

    @objc func toggleLightDark(_ sender: Any?) {
        schemeController?.toggleLightDark()
    }

    @objc func reloadSchemes(_ sender: Any?) {
        schemeController?.reload()
    }

    @objc func openThemesFolder(_ sender: Any?) {
        schemeController?.openThemesFolder()
    }

    @objc func toggleHighlightCurrentLine(_ sender: Any?) {
        guard let model else { return }
        model.setHighlightCurrentLine(!model.settings.highlightCurrentLine)
    }

    @objc func increaseFontSize(_ sender: Any?) {
        fontController?.increaseFontSize()
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        fontController?.decreaseFontSize()
    }

    @objc func resetFontSize(_ sender: Any?) {
        fontController?.resetFontSize()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleHighlightCurrentLine(_:)):
            // The checkbox reads the setting each time the menu opens, so a change made in
            // Settings shows here without the menu being told.
            menuItem.state = model?.settings.highlightCurrentLine == true ? .on : .off
            return model != nil
        case #selector(showSettings(_:)), #selector(toggleLightDark(_:)), #selector(reloadSchemes(_:)),
             #selector(openThemesFolder(_:)), #selector(increaseFontSize(_:)), #selector(decreaseFontSize(_:)),
             #selector(resetFontSize(_:)):
            return model != nil
        default:
            return true
        }
    }

    #if DEBUG
    /// Launch checks without GUI access, run 0.5 s after launch in this order:
    /// - `FROMSCRATCH_DEBUG_APPEND=<text>` appends that text through the typing path.
    /// - `FROMSCRATCH_DEBUG_SELECT=<loc,len>[;<loc,len>...]` sets the selection (UTF-16 ranges).
    /// - `FROMSCRATCH_DEBUG_COMMAND=<selector> ...` sends each action (space-separated, e.g.
    ///   `toggleCheckbox: undo:`) to the first of the text view, the window controller, the window
    ///   and the app that responds, as a menu item would after validation.
    /// - `FROMSCRATCH_DEBUG_KEYS=<key> ...` synthesises key-down events: modified keys go through
    ///   the main menu first (the item with that shortcut, dispatched up the responder chain),
    ///   anything else, or a key no menu item takes, to the window. Keys are `cmd+l`, `opt+cmd+up`, `ctrl+g`,
    ///   `shift+tab`, `return`, `esc`, `tab`, and `text:<characters>` to type characters.
    /// - `FROMSCRATCH_DEBUG_THEN=terminate` then sends the action ⌘Q sends (`terminate:`), `=close`
    ///   sends the window the action ⌘W sends (`performClose:`), and `=zoom-close` zooms the
    ///   window, waits 1 s, then closes it.
    /// - `FROMSCRATCH_DEBUG_SETTINGS=<step>|<step>...` (after the commands, before the keys), each
    ///   step followed by a log of the scheme, colours, band, font and Settings state:
    ///   `scheme:<id>` (SchemeController.select), `schemes:all` (every scheme in turn),
    ///   `highlight:on|off` (the Settings toggle's binding), `menu:<title>` (the main-menu item
    ///   with that title, sent as a click would be), `font:<PostScript name>:<size>` (as if picked
    ///   in the font panel), `trait:bold` (the font manager's Bold, delivered through
    ///   `changeFont:` to its target), `settings:open`, `settings:press:<label>` (presses the
    ///   control with that accessibility label in the Settings window), `select:<loc,len>`,
    ///   `choose-font` (Settings › Choose…), `reload`, `update:dismiss` (clicks the update bar's ×), `log`.
    /// `FROMSCRATCH_DEBUG_LATEST_TAG=<tag>` replaces the GitHub release check with that tag.
    /// `FROMSCRATCH_DEBUG_ACTIVATE=1` first activates the app and makes the window key (it takes
    /// focus from the frontmost app). `FROMSCRATCH_DEBUG_MENU=1` then logs every menu item with its shortcut and whether it is
    /// enabled. Each step logs the text, selection and undo name with the prefix `FROMSCRATCH_DEBUG`.
    private func runDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        guard let editor else { return }
        let hookNames = ["FROMSCRATCH_DEBUG_ACTIVATE", "FROMSCRATCH_DEBUG_MENU", "FROMSCRATCH_DEBUG_APPEND",
                         "FROMSCRATCH_DEBUG_SELECT", "FROMSCRATCH_DEBUG_COMMAND", "FROMSCRATCH_DEBUG_SETTINGS",
                         "FROMSCRATCH_DEBUG_KEYS",
                         "FROMSCRATCH_DEBUG_THEN"]
        guard hookNames.contains(where: { env[$0] != nil }) else { return }
        let then = env["FROMSCRATCH_DEBUG_THEN"]
        Task { @MainActor in
            if env["FROMSCRATCH_DEBUG_ACTIVATE"] != nil {
                // Menu items targeting the responder chain validate only with a key window, which
                // a process launched from a shell does not always get. Takes focus from other apps.
                NSRunningApplication.current.activate(options: [.activateAllWindows])
                editor.window?.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .milliseconds(500))
            NSLog("FROMSCRATCH_DEBUG app active: %@; window key: %@", NSApp.isActive ? "yes" : "no",
                  editor.window?.isKeyWindow == true ? "yes" : "no")
            if env["FROMSCRATCH_DEBUG_MENU"] != nil, let main = NSApp.mainMenu {
                debugLogMenu(main, path: "")
            }
            if let text = env["FROMSCRATCH_DEBUG_APPEND"] {
                editor.debugAppend(text)
            }
            if let spec = env["FROMSCRATCH_DEBUG_SELECT"] {
                editor.debugSelect(spec)
            }
            for name in (env["FROMSCRATCH_DEBUG_COMMAND"] ?? "").split(separator: " ") {
                let action = NSSelectorFromString(String(name))
                let candidates: [AnyObject?] = [editor.textView, editor, editor.window, NSApp, self]
                let target = candidates.compactMap { $0 }.first { $0.responds(to: action) }
                let sent = NSApp.sendAction(action, to: target, from: nil)
                NSLog("FROMSCRATCH_DEBUG command %@ sent: %@; %@", String(name), sent ? "yes" : "no", editor.debugState())
                try? await Task.sleep(for: .milliseconds(200))
            }
            for step in (env["FROMSCRATCH_DEBUG_SETTINGS"] ?? "").split(separator: "|") {
                await debugSettingsStep(String(step), editor: editor)
            }
            for key in (env["FROMSCRATCH_DEBUG_KEYS"] ?? "").split(separator: " ") {
                let route = debugPress(String(key), in: editor)
                try? await Task.sleep(for: .milliseconds(300))
                NSLog("FROMSCRATCH_DEBUG key %@ via %@; %@", String(key), route, editor.debugState())
            }
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

    private func debugSettingsStep(_ step: String, editor: EditorWindowController) async {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let (name, argument) = (parts.first ?? "", parts.count > 1 ? parts[1] : "")
        var note = ""
        switch name {
        case "scheme":
            schemeController?.select(id: argument)
        case "schemes" where argument == "all":
            for scheme in model?.schemes.all ?? [] {
                schemeController?.select(id: scheme.id)
                try? await Task.sleep(for: .milliseconds(150))
                NSLog("FROMSCRATCH_DEBUG settings scheme:%@; %@", scheme.id, editor.debugAppearance())
            }
            return
        case "highlight":
            settingsWindow?.viewModel.highlightCurrentLine = argument == "on"
        case "menu":
            if let menu = NSApp.mainMenu, let item = Self.debugMenuItem(titled: argument, in: menu), let action = item.action {
                let sent = NSApp.sendAction(action, to: item.target, from: item)
                note = "sent=\(sent)"
            } else {
                note = "no item titled \(argument)"
            }
        case "font":
            let pieces = argument.split(separator: ":").map(String.init)
            if pieces.count == 2, let size = Double(pieces[1]), let font = NSFont(name: pieces[0], size: size) {
                fontController?.store(font)
            } else {
                note = "no font \(argument)"
            }
        case "trait" where argument == "bold":
            let item = NSMenuItem()
            item.tag = Int(NSFontTraitMask.boldFontMask.rawValue)
            NSFontManager.shared.addFontTrait(item)
        case "settings" where argument == "open":
            showSettings(nil)
        case "settings" where argument.hasPrefix("press:"):
            let label = String(argument.dropFirst("press:".count))
            note = debugPress(label: label)
        case "reload":
            schemeController?.reload()
        case "update" where argument == "dismiss":
            note = "clicked=\(editor.debugDismissUpdate())"
        case "select":
            // Moves the caret or selection after launch, so a capture shows whether the old band
            // was redrawn away.
            editor.debugSelect(argument)
        case "choose-font":
            settingsWindow?.viewModel.chooseFont()
            let selected = NSFontManager.shared.selectedFont
            note = "fontPanelVisible=\(NSFontPanel.shared.isVisible) selectedFont=\(selected?.fontName ?? "-") \(selected?.pointSize ?? 0)"
        default:
            break
        }
        try? await Task.sleep(for: .milliseconds(250))
        NSLog("FROMSCRATCH_DEBUG settings %@ %@; %@; %@", step, note, editor.debugAppearance(), debugSettingsState())
    }

    /// The Settings window and View menu as the user would see them.
    private func debugSettingsState() -> String {
        var highlightItem = "-"
        if let menu = NSApp.mainMenu, let item = Self.debugMenuItem(titled: "Highlight Current Line", in: menu) {
            _ = validateMenuItem(item)
            highlightItem = item.state == .on ? "on" : "off"
        }
        var checkedScheme = "-"
        if let menu = NSApp.mainMenu, let holder = Self.debugMenuItem(titled: "Colour Scheme", in: menu),
           let submenu = holder.submenu {
            submenu.delegate?.menuNeedsUpdate?(submenu)
            checkedScheme = submenu.items.filter { $0.state == .on }.map(\.title).joined(separator: ",")
        }
        let window = settingsWindow?.window
        let vm = settingsWindow?.viewModel
        return """
            menu[highlight=\(highlightItem) checkedScheme=\(checkedScheme)] \
            settingsWindow[visible=\(window?.isVisible ?? false) title=\(window?.title ?? "-") \
            frame=\(window.map { NSStringFromRect($0.frame) } ?? "-") resizable=\(window?.styleMask.contains(.resizable) ?? false) \
            miniaturizable=\(window?.styleMask.contains(.miniaturizable) ?? false)] \
            settingsModel[scheme=\(vm?.selectedSchemeId ?? "-") font=\(vm?.fontDescription ?? "-") \
            highlight=\(vm?.highlightCurrentLine ?? false)] \
            stored[font=\(model.map { "\($0.settings.font)" } ?? "-")] \
            fontManagerTarget=\(NSFontManager.shared.target === fontController ? "FontController" : "other")
            """
    }

    /// Presses the first control in the Settings window whose accessibility label or title
    /// contains `label`, the way VoiceOver would.
    private func debugPress(label: String) -> String {
        guard let root = settingsWindow?.window?.contentView else { return "no settings window" }
        var found: [String] = []
        func search(_ element: Any, depth: Int) -> NSAccessibilityProtocol? {
            guard depth < 30, let element = element as? NSAccessibilityProtocol else { return nil }
            let role = element.accessibilityRole()?.rawValue ?? ""
            let text = [element.accessibilityLabel(), element.accessibilityTitle()].compactMap { $0 }.joined(separator: "/")
            if !text.isEmpty { found.append("\(role):\(text)") }
            if text.contains(label), [NSAccessibility.Role.button, .checkBox, .popUpButton].map(\.rawValue).contains(role) {
                return element
            }
            for child in element.accessibilityChildren() ?? [] {
                if let hit = search(child, depth: depth + 1) { return hit }
            }
            return nil
        }
        guard let hit = search(root, depth: 0) else {
            return "nothing labelled \(label); saw \(found.joined(separator: " | "))"
        }
        let pressed = hit.accessibilityPerformPress()
        return "pressed \(hit.accessibilityRole()?.rawValue ?? "?") \(label): \(pressed)"
    }

    private static func debugMenuItem(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu {
                submenu.delegate?.menuNeedsUpdate?(submenu)
                if let found = debugMenuItem(titled: title, in: submenu) { return found }
            }
        }
        return nil
    }

    private func debugLogMenu(_ menu: NSMenu, path: String) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        for item in menu.items where !item.isSeparatorItem {
            let name = path.isEmpty ? item.title : "\(path) > \(item.title)"
            if let submenu = item.submenu {
                debugLogMenu(submenu, path: name)
                continue
            }
            NSLog("FROMSCRATCH_DEBUG menu %@ | key %@ mods %lu | action %@ | enabled %@%@", name,
                  item.keyEquivalent.debugDescription, item.keyEquivalentModifierMask.rawValue,
                  item.action.map(NSStringFromSelector) ?? "-", item.isEnabled ? "yes" : "no",
                  item.isHidden ? " (hidden)" : "")
        }
    }

    /// Delivers one synthetic key press and says which path took it.
    private func debugPress(_ token: String, in editor: EditorWindowController) -> String {
        guard let window = editor.window else { return "no window" }
        if token.hasPrefix("text:") {
            for character in token.dropFirst(5) {
                if let event = Self.debugKeyEvent(characters: String(character), ignoring: String(character),
                                                  modifiers: [], keyCode: 0, window: window) {
                    window.sendEvent(event)
                }
            }
            return "window (typed)"
        }
        var parts = token.split(separator: "+").map(String.init)
        let base = parts.removeLast()
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "opt": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return "unknown modifier \(part)"
            }
        }
        let named: [String: (String, UInt16)] = [
            "return": ("\r", 36), "esc": ("\u{1b}", 53), "tab": ("\t", 48),
            "up": (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126),
            "down": (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125),
            "right": (String(UnicodeScalar(NSRightArrowFunctionKey)!), 124),
        ]
        let keyCodes: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "q": 12,
            "w": 13, "e": 14, "t": 17, "=": 24, "-": 27, "0": 29, "i": 34, "l": 37, ",": 43, "/": 44, "m": 46,
        ]
        var characters: String
        var keyCode: UInt16
        if let (chars, code) = named[base] {
            characters = chars
            keyCode = code
        } else {
            characters = base
            keyCode = keyCodes[base] ?? 0
        }
        if ["up", "down", "right"].contains(base) { modifiers.formUnion([.numericPad, .function]) }
        if modifiers.contains(.shift), base == "tab" { characters = "\u{19}" }  // back-tab, as AppKit reports it
        else if modifiers.contains(.shift) { characters = characters.uppercased() }
        let ignoring = characters
        // Real events carry the control character for ⌃-letter combinations.
        if modifiers.contains(.control), let scalar = characters.unicodeScalars.first, scalar.isASCII,
           scalar.properties.isAlphabetic {
            characters = String(UnicodeScalar(UInt8(scalar.value & 0x1f)))
        }
        guard let event = Self.debugKeyEvent(characters: characters, ignoring: ignoring, modifiers: modifiers,
                                             keyCode: keyCode, window: window) else { return "no event" }
        if !modifiers.intersection([.command, .control]).isEmpty, let menu = NSApp.mainMenu,
           let item = Self.debugMenuItem(matching: event, in: menu), let action = item.action {
            // NSMenu.performKeyEquivalent would validate against the key window, which a process
            // launched from a shell does not get, so the item found here is dispatched the way a
            // nil-targeted menu action travels: up the window's responder chain, then the app.
            let performed: Bool
            if let target = item.target {
                performed = NSApp.sendAction(action, to: target, from: item)
            } else {
                performed = window.firstResponder?.tryToPerform(action, with: item) == true
                    || NSApp.tryToPerform(action, with: item)
            }
            return "menu item \"\(item.title)\" \(NSStringFromSelector(action)) (\(performed ? "performed" : "no responder"))"
        }
        window.sendEvent(event)
        return "window"
    }

    /// The menu item whose shortcut is this event's key and modifiers.
    private static func debugMenuItem(matching event: NSEvent, in menu: NSMenu) -> NSMenuItem? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        for item in menu.items {
            if let submenu = item.submenu, let found = debugMenuItem(matching: event, in: submenu) { return found }
            if !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key,
               item.keyEquivalentModifierMask == modifiers {
                return item
            }
        }
        return nil
    }

    private static func debugKeyEvent(characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags,
                                      keyCode: UInt16, window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: keyCode)
    }
    #endif
}

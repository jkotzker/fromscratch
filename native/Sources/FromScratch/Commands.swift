import AppKit

/// Every command that has a menu item. The raw value is a stable name, so a later keybinding
/// setting can refer to commands without depending on titles or selectors.
enum CommandID: String, CaseIterable {
    // App menu
    case openWebsite, openSupport, checkForUpdates, showSettings
    case hideApp, hideOthers, showAll, quit
    // File
    case close, saveNow
    // Edit
    case undo, redo, cut, copy, paste, selectAll
    case find, findAndReplace, findNext, findPrevious, useSelectionForFind
    case toggleCheckbox, toggleCheckboxAlternate, deleteLine, moveLineUp, moveLineDown, goToLine
    // View
    case toggleLightDark, reloadSchemes, openThemesFolder, toggleHighlightCurrentLine
    case increaseFontSize, increaseFontSizeAlternate, decreaseFontSize, resetFontSize
    case showFonts, toggleFullScreen
    // Window
    case minimize, zoom, bringAllToFront
}

/// Where a command's menu item goes. `.find` is the Find submenu inside Edit; `.colourScheme` is
/// the Colour Scheme submenu inside View, whose scheme items are added when it opens.
enum MenuPlacement {
    case app, file, edit, find, view, colourScheme, window
}

/// Who receives the action. Almost everything goes up the responder chain (a nil target); the
/// font panel is opened by the shared font manager, which is not in the chain.
enum CommandTarget {
    case responderChain
    case fontManager
}

/// One row of the command table: everything needed to build its menu item and shortcut.
struct CommandSpec {
    let id: CommandID
    let title: String
    /// The key equivalent as AppKit takes it (lower case; Shift is in `modifiers`). Empty for none.
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: Selector
    let menu: MenuPlacement
    /// Items with different groups in the same menu are separated by a separator.
    let group: Int
    /// `NSTextFinder.Action` raw value for the Find items, which all share one action.
    var tag: Int = 0
    var target: CommandTarget = .responderChain
    /// A hidden item that only adds a second shortcut for the command before it (⌘/ for the
    /// checkbox, ⌘= for a bigger font), as v2's `visible: false` menu entries did.
    var isAlternate: Bool = false
}

/// The single source of menu items and key equivalents. A configurable-keybindings setting can
/// later replace `defaults` without touching the menu builder or the views.
@MainActor
enum Commands {
    static let appName = "FromScratch"
    // REPO_URL in src/main/menu.js.
    static let repositoryURL = URL(string: "https://github.com/jkotzker/fromscratch")!
    static let websiteURL = URL(string: "https://fromscratch.rocks")!

    private static let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    private static let downArrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)

    private static func finder(_ id: CommandID, _ title: String, _ key: String,
                               _ modifiers: NSEvent.ModifierFlags, _ action: NSTextFinder.Action) -> CommandSpec {
        CommandSpec(id: id, title: title, key: key, modifiers: modifiers,
                    action: #selector(NSResponder.performTextFinderAction(_:)), menu: .find, group: 0,
                    tag: action.rawValue)
    }

    // Shortcuts are the spec's Editing table plus the macOS standards; titles follow v2's menu.js
    // in Mac title case.
    static let defaults: [CommandSpec] = [
        // App menu. Website, Support and Check for Updates open the same pages as v2.
        CommandSpec(id: .openWebsite, title: "Website", key: "", modifiers: [],
                    action: #selector(AppDelegate.openWebsite(_:)), menu: .app, group: 0),
        CommandSpec(id: .openSupport, title: "Support", key: "", modifiers: [],
                    action: #selector(AppDelegate.openSupport(_:)), menu: .app, group: 0),
        CommandSpec(id: .checkForUpdates, title: "Check for Updates…", key: "", modifiers: [],
                    action: #selector(AppDelegate.checkForUpdates(_:)), menu: .app, group: 0),
        CommandSpec(id: .showSettings, title: "Settings…", key: ",", modifiers: [.command],
                    action: #selector(AppDelegate.showSettings(_:)), menu: .app, group: 1),
        CommandSpec(id: .hideApp, title: "Hide \(appName)", key: "h", modifiers: [.command],
                    action: #selector(NSApplication.hide(_:)), menu: .app, group: 3),
        CommandSpec(id: .hideOthers, title: "Hide Others", key: "h", modifiers: [.command, .option],
                    action: #selector(NSApplication.hideOtherApplications(_:)), menu: .app, group: 3),
        CommandSpec(id: .showAll, title: "Show All", key: "", modifiers: [],
                    action: #selector(NSApplication.unhideAllApplications(_:)), menu: .app, group: 3),
        CommandSpec(id: .quit, title: "Quit \(appName)", key: "q", modifiers: [.command],
                    action: #selector(NSApplication.terminate(_:)), menu: .app, group: 4),

        // File
        CommandSpec(id: .close, title: "Close", key: "w", modifiers: [.command],
                    action: #selector(NSWindow.performClose(_:)), menu: .file, group: 0),
        CommandSpec(id: .saveNow, title: "Save", key: "s", modifiers: [.command],
                    action: #selector(EditorWindowController.saveNow(_:)), menu: .file, group: 0),

        // Edit
        CommandSpec(id: .undo, title: "Undo", key: "z", modifiers: [.command],
                    action: Selector(("undo:")), menu: .edit, group: 0),
        CommandSpec(id: .redo, title: "Redo", key: "z", modifiers: [.command, .shift],
                    action: Selector(("redo:")), menu: .edit, group: 0),
        CommandSpec(id: .cut, title: "Cut", key: "x", modifiers: [.command],
                    action: #selector(NSText.cut(_:)), menu: .edit, group: 1),
        CommandSpec(id: .copy, title: "Copy", key: "c", modifiers: [.command],
                    action: #selector(NSText.copy(_:)), menu: .edit, group: 1),
        CommandSpec(id: .paste, title: "Paste", key: "v", modifiers: [.command],
                    action: #selector(NSText.paste(_:)), menu: .edit, group: 1),
        CommandSpec(id: .selectAll, title: "Select All", key: "a", modifiers: [.command],
                    action: #selector(NSText.selectAll(_:)), menu: .edit, group: 1),
        finder(.find, "Find…", "f", [.command], .showFindInterface),
        finder(.findAndReplace, "Find and Replace…", "f", [.command, .option], .showReplaceInterface),
        finder(.findNext, "Find Next", "g", [.command], .nextMatch),
        finder(.findPrevious, "Find Previous", "g", [.command, .shift], .previousMatch),
        finder(.useSelectionForFind, "Use Selection for Find", "e", [.command], .setSearchString),
        CommandSpec(id: .toggleCheckbox, title: "Toggle Checkbox", key: "l", modifiers: [.command],
                    action: #selector(EditorTextView.toggleCheckbox(_:)), menu: .edit, group: 3),
        CommandSpec(id: .toggleCheckboxAlternate, title: "Toggle Checkbox", key: "/", modifiers: [.command],
                    action: #selector(EditorTextView.toggleCheckbox(_:)), menu: .edit, group: 3,
                    isAlternate: true),
        CommandSpec(id: .deleteLine, title: "Delete Line", key: "d", modifiers: [.command],
                    action: #selector(EditorTextView.deleteLine(_:)), menu: .edit, group: 3),
        // ⌥⌘ rather than v2's ⌘ keeps ⌘↑/⌘↓ as the macOS start and end of document.
        CommandSpec(id: .moveLineUp, title: "Move Line Up", key: upArrow, modifiers: [.command, .option],
                    action: #selector(EditorTextView.moveLineUp(_:)), menu: .edit, group: 3),
        CommandSpec(id: .moveLineDown, title: "Move Line Down", key: downArrow, modifiers: [.command, .option],
                    action: #selector(EditorTextView.moveLineDown(_:)), menu: .edit, group: 3),
        // ⌃G because ⌘G is Find Next on the Mac (v2 used Mod-g).
        CommandSpec(id: .goToLine, title: "Go to Line…", key: "g", modifiers: [.control],
                    action: #selector(EditorWindowController.showGoToLine(_:)), menu: .edit, group: 4),

        // View, in v2's order (menu.js): theme toggle, Colour Scheme, highlight, then font size.
        CommandSpec(id: .toggleLightDark, title: "Toggle Light/Dark", key: "i", modifiers: [.command],
                    action: #selector(AppDelegate.toggleLightDark(_:)), menu: .view, group: 0),
        // Below the scheme items in View › Colour Scheme. No shortcuts, as in v2.
        CommandSpec(id: .reloadSchemes, title: "Reload Schemes", key: "", modifiers: [],
                    action: #selector(AppDelegate.reloadSchemes(_:)), menu: .colourScheme, group: 0),
        CommandSpec(id: .openThemesFolder, title: "Open Themes Folder", key: "", modifiers: [],
                    action: #selector(AppDelegate.openThemesFolder(_:)), menu: .colourScheme, group: 0),
        // No shortcut: v2 left it without one, as a setting changed once.
        CommandSpec(id: .toggleHighlightCurrentLine, title: "Highlight Current Line", key: "", modifiers: [],
                    action: #selector(AppDelegate.toggleHighlightCurrentLine(_:)), menu: .view, group: 0),
        CommandSpec(id: .increaseFontSize, title: "Increase Font Size", key: "+", modifiers: [.command],
                    action: #selector(AppDelegate.increaseFontSize(_:)), menu: .view, group: 1),
        // The unshifted key, which is what people actually press (v2 menu.js).
        CommandSpec(id: .increaseFontSizeAlternate, title: "Increase Font Size", key: "=", modifiers: [.command],
                    action: #selector(AppDelegate.increaseFontSize(_:)), menu: .view, group: 1, isAlternate: true),
        CommandSpec(id: .decreaseFontSize, title: "Decrease Font Size", key: "-", modifiers: [.command],
                    action: #selector(AppDelegate.decreaseFontSize(_:)), menu: .view, group: 1),
        CommandSpec(id: .resetFontSize, title: "Reset Font Size", key: "0", modifiers: [.command],
                    action: #selector(AppDelegate.resetFontSize(_:)), menu: .view, group: 1),
        CommandSpec(id: .showFonts, title: "Show Fonts", key: "t", modifiers: [.command],
                    action: #selector(NSFontManager.orderFrontFontPanel(_:)), menu: .view, group: 2,
                    target: .fontManager),
        // AppKit retitles this item "Exit Full Screen" while the window is in full screen. On
        // macOS 15 it also gives it the Globe-F shortcut when the menu is installed and adds a
        // hidden ⌃⌘F twin that still answers the key (measured with the debug menu log), so the
        // View menu shows one item and both shortcuts work.
        CommandSpec(id: .toggleFullScreen, title: "Enter Full Screen", key: "f", modifiers: [.control, .command],
                    action: #selector(NSWindow.toggleFullScreen(_:)), menu: .view, group: 3),

        // Window: the standard items, so ⌘M works and the window is listed.
        CommandSpec(id: .minimize, title: "Minimize", key: "m", modifiers: [.command],
                    action: #selector(NSWindow.performMiniaturize(_:)), menu: .window, group: 0),
        CommandSpec(id: .zoom, title: "Zoom", key: "", modifiers: [],
                    action: #selector(NSWindow.performZoom(_:)), menu: .window, group: 0),
        CommandSpec(id: .bringAllToFront, title: "Bring All to Front", key: "", modifiers: [],
                    action: #selector(NSApplication.arrangeInFront(_:)), menu: .window, group: 1),
    ]

    static func spec(_ id: CommandID) -> CommandSpec? {
        defaults.first { $0.id == id }
    }

    /// The undo action name for a command: its menu title without an ellipsis.
    static func undoName(_ id: CommandID) -> String {
        (spec(id)?.title ?? id.rawValue).replacingOccurrences(of: "…", with: "")
    }
}

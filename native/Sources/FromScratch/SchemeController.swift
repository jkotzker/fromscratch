import AppKit
import FromScratchCore

/// Choosing, toggling and reloading colour schemes, and the View › Colour Scheme submenu.
/// Mirrors selectScheme, rescanSchemes and the scheme submenu in src/main/index.js and menu.js.
@MainActor
final class SchemeController: NSObject, NSMenuDelegate {
    private let model: AppModel
    /// Opens the themes folder; replaced in tests so nothing opens in Finder.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Scheme items and the separator after them carry this tag, so a rebuild can find and
    /// replace them without touching the table-built commands below.
    private static let schemeItemTag = 0x5C4E

    init(model: AppModel) {
        self.model = model
    }

    var themesDirectory: URL {
        model.dataDirectory.appendingPathComponent(SchemeLibrary.themesDirname, isDirectory: true)
    }

    /// Stores the id and shows the scheme. An id that does not resolve stores the scheme it
    /// resolved to, as selectScheme does in v2.
    func select(id: String) {
        let scheme = model.schemes.resolve(id: id)
        model.settings.colorSchemeId = scheme.id
        model.apply(scheme: scheme)
    }

    /// toggleScheme in App.jsx: the first scheme whose darkness differs from the current one.
    /// The built-ins come first, so in practice this is the opposite built-in.
    func toggleLightDark() {
        let isDark = model.scheme.isDark
        guard let target = model.schemes.all.first(where: { $0.isDark != isDark }) else { return }
        select(id: target.id)
    }

    /// Rescans the themes folder. The stored id is resolved again, so an edited theme file shows
    /// its new colours and a deleted one falls back to Dark; the setting itself is left alone.
    func reload() {
        model.schemes.rescan()
        model.apply(scheme: model.schemes.resolve(id: model.settings.colorSchemeId))
    }

    /// Opens the themes folder in Finder, creating it first so there is always somewhere to look.
    func openThemesFolder() {
        let directory = themesDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Could not create the themes folder \(directory.path): \(error)")
            NSSound.beep()
            return
        }
        openURL(directory)
    }

    // MARK: Colour Scheme submenu

    /// Built-ins first, then the files, with a radio-style checkmark on the scheme in use (the
    /// resolved one, as v2's menu did, so a deleted theme's id never leaves nothing checked).
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.schemeItemTag {
            menu.removeItem(item)
        }
        let activeID = model.scheme.id
        var index = 0
        for scheme in model.schemes.all {
            let item = NSMenuItem(title: scheme.name, action: #selector(selectSchemeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scheme.id
            item.tag = Self.schemeItemTag
            item.state = scheme.id == activeID ? .on : .off
            menu.insertItem(item, at: index)
            index += 1
        }
        if index < menu.items.count {
            let separator = NSMenuItem.separator()
            separator.tag = Self.schemeItemTag
            menu.insertItem(separator, at: index)
        }
    }

    @objc func selectSchemeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        select(id: id)
    }
}

import AppKit

/// Builds the menu bar from the command table. Nothing here knows a shortcut: every title, key
/// and action comes from the `CommandSpec`s it is given.
@MainActor
enum MainMenu {
    static func build(from specs: [CommandSpec]) -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(title: Commands.appName)
        let file = NSMenu(title: "File")
        let edit = NSMenu(title: "Edit")
        let find = NSMenu(title: "Find")
        let view = NSMenu(title: "View")
        let window = NSMenu(title: "Window")
        var lastGroup: [ObjectIdentifier: Int] = [:]

        func add(_ item: NSMenuItem, to menu: NSMenu, group: Int) {
            if let previous = lastGroup[ObjectIdentifier(menu)], previous != group {
                menu.addItem(.separator())
            }
            lastGroup[ObjectIdentifier(menu)] = group
            menu.addItem(item)
        }

        for spec in specs {
            let item = makeItem(spec)
            switch spec.menu {
            case .app: add(item, to: app, group: spec.group)
            case .file: add(item, to: file, group: spec.group)
            case .edit: add(item, to: edit, group: spec.group)
            case .view: add(item, to: view, group: spec.group)
            case .window: add(item, to: window, group: spec.group)
            case .find:
                // The submenu takes the place of the first Find command among the Edit items.
                if find.items.isEmpty {
                    let holder = NSMenuItem(title: find.title, action: nil, keyEquivalent: "")
                    holder.submenu = find
                    add(holder, to: edit, group: -1)
                }
                find.addItem(item)
            }
        }

        // Services is AppKit's to fill, so it is not a command; it goes before the Hide items.
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: services.title, action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        if let hide = app.items.firstIndex(where: { $0.action == #selector(NSApplication.hide(_:)) }) {
            app.insertItem(servicesItem, at: hide)
            app.insertItem(.separator(), at: hide + 1)
        } else {
            app.addItem(servicesItem)
        }
        NSApp?.servicesMenu = services

        for submenu in [app, file, edit, view, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        // AppKit lists the open windows here.
        NSApp?.windowsMenu = window
        return main
    }

    private static func makeItem(_ spec: CommandSpec) -> NSMenuItem {
        let item = NSMenuItem(title: spec.title, action: spec.action, keyEquivalent: spec.key)
        item.keyEquivalentModifierMask = spec.modifiers
        item.tag = spec.tag
        switch spec.target {
        case .responderChain: item.target = nil
        case .fontManager: item.target = NSFontManager.shared
        }
        if spec.isAlternate {
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        return item
    }
}

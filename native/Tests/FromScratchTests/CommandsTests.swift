import AppKit
import Testing
@testable import FromScratch

/// A shortcut as AppKit matches it: an upper-case letter key implies Shift, and only the
/// device-independent modifiers count.
private struct Shortcut: Hashable {
    let key: String
    let modifiers: UInt

    init(_ spec: CommandSpec) {
        var modifiers = spec.modifiers.intersection(.deviceIndependentFlagsMask)
        if spec.key.count == 1, spec.key.lowercased() != spec.key { modifiers.insert(.shift) }
        key = spec.key.lowercased()
        self.modifiers = modifiers.rawValue
    }
}

private func allItems(in menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map(allItems(in:)) ?? []) }
}

@MainActor
struct CommandsTests {
    @Test func noDuplicateShortcuts() {
        var seen: [Shortcut: CommandID] = [:]
        for spec in Commands.defaults where !spec.key.isEmpty {
            let shortcut = Shortcut(spec)
            #expect(seen[shortcut] == nil, "\(spec.id) reuses the shortcut of \(seen[shortcut].map { "\($0)" } ?? "")")
            seen[shortcut] = spec.id
        }
    }

    @Test func noDuplicateIDs() {
        let ids = Commands.defaults.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(CommandID.allCases))
    }

    /// Every spec becomes exactly one menu item carrying its action, key, modifiers and tag.
    @Test func everySpecHasAMenu() {
        let items = allItems(in: MainMenu.build(from: Commands.defaults))
        for spec in Commands.defaults {
            let matches = items.filter {
                $0.action == spec.action && $0.keyEquivalent == spec.key
                    && $0.keyEquivalentModifierMask == spec.modifiers && $0.tag == spec.tag
            }
            #expect(matches.count == 1, "\(spec.id) has \(matches.count) menu items")
            if let item = matches.first {
                #expect(item.title == spec.title)
                // Alternates only add a second shortcut; they must still fire while hidden.
                #expect(item.isHidden == spec.isAlternate)
                if spec.isAlternate { #expect(item.allowsKeyEquivalentWhenHidden) }
            }
        }
    }

    /// The table's placement decides the top-level menu, and Find items live in Edit › Find.
    @Test func specsLandInTheirMenus() throws {
        let main = MainMenu.build(from: Commands.defaults)
        let titles = main.items.map(\.title)
        #expect(titles == ["FromScratch", "File", "Edit", "View", "Window"])
        let edit = try #require(main.item(withTitle: "Edit")?.submenu)
        let find = try #require(edit.item(withTitle: "Find")?.submenu)
        let findSpecs = Commands.defaults.filter { $0.menu == .find }
        #expect(find.items.map(\.action) == findSpecs.map(\.action))
        // Find items act through NSTextFinder, which reads the action from the tag.
        #expect(findSpecs.map(\.tag) == [
            NSTextFinder.Action.showFindInterface, .showReplaceInterface, .nextMatch, .previousMatch, .setSearchString,
        ].map(\.rawValue))
        let view = try #require(main.item(withTitle: "View")?.submenu)
        let showFonts = try #require(view.items.first { $0.action == #selector(NSFontManager.orderFrontFontPanel(_:)) })
        #expect(showFonts.target === NSFontManager.shared)
    }

    /// Catches a misspelt selector: every action in the table must be implemented by something in
    /// the responder chain, except the ones Task 10 implements (disabled until then).
    @Test func everyActionHasAnImplementation() {
        let pendingTask10: Set<Selector> = [
            Selector(("toggleLightDark:")), Selector(("increaseFontSize:")), Selector(("decreaseFontSize:")),
            Selector(("resetFontSize:")), Selector(("showSettings:")),
        ]
        let responders: [AnyClass] = [
            EditorTextView.self, EditorWindowController.self, AppDelegate.self,
            NSApplication.self, NSWindow.self, NSFontManager.self,
        ]
        for spec in Commands.defaults where !pendingTask10.contains(spec.action) {
            #expect(responders.contains { $0.instancesRespond(to: spec.action) }, "nothing implements \(spec.action)")
        }
    }

    @Test func specsListedInTheBriefHaveTheirDefaultShortcuts() throws {
        func spec(_ id: CommandID) throws -> CommandSpec { try #require(Commands.spec(id)) }
        #expect(try spec(.toggleCheckbox).key == "l")
        #expect(try spec(.toggleCheckboxAlternate).key == "/")
        #expect(try spec(.deleteLine).key == "d")
        #expect(try spec(.moveLineUp).modifiers == [.command, .option])
        #expect(try spec(.goToLine).modifiers == [.control])
        #expect(try spec(.goToLine).key == "g")
        #expect(try spec(.saveNow).action == #selector(EditorWindowController.saveNow(_:)))
        #expect(try spec(.toggleFullScreen).modifiers == [.control, .command])
    }
}

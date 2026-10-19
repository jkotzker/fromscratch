import AppKit
import FromScratchCore
import Testing
@testable import FromScratch

/// The top of the editor window: the titlebar inset the text and the find bar respect, the
/// taller drag strip, and the full-screen menu item. Windows are built but never shown.
@MainActor
@Suite(.serialized)
struct WindowChromeTests {
    private static let text = (1...40).map { "Synthetic line \($0)" }.joined(separator: "\n")

    private func makeEditor() throws -> EditorWindowController {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FromScratchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.text.utf8).write(to: directory.appendingPathComponent(ContentStore.fileName))
        let editor = EditorWindowController(model: AppModel(dataDirectory: directory))
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        return editor
    }

    /// The topmost view at `fromTop` points below the window's top edge, as a click would find it.
    private func hit(_ editor: EditorWindowController, x: CGFloat? = nil, fromTop: CGFloat) throws -> NSView? {
        let content = try #require(editor.window?.contentView)
        let frame = try #require(content.superview)
        frame.layoutSubtreeIfNeeded()
        let point = content.convert(NSPoint(x: x ?? content.bounds.midX, y: content.bounds.maxY - fromTop), to: nil)
        return frame.hitTest(point)
    }

    private func isInside(_ view: NSView?, _ ancestor: NSView) -> Bool {
        view.map { $0 === ancestor || $0.isDescendant(of: ancestor) } ?? false
    }

    private func showFindBar(_ editor: EditorWindowController) {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.textView.performTextFinderAction(item)
        editor.scrollView.tile()
        editor.window?.contentView?.layoutSubtreeIfNeeded()
    }

    // MARK: Titlebar inset

    @Test func scrollViewInsetIsTheTitlebarFromContentLayoutRect() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let content = try #require(window.contentView)
        let layout = content.convert(window.contentLayoutRect, from: nil)
        let titlebar = content.bounds.maxY - layout.maxY
        // A transparent titlebar without a toolbar; whatever its height, the inset follows it.
        #expect(titlebar > 0)
        #expect(EditorWindowController.titlebarHeight(of: window) == titlebar)
        #expect(editor.scrollView.contentInsets.top == titlebar)
        #expect(!editor.scrollView.automaticallyAdjustsContentInsets)
    }

    @Test func firstLineStays48PointsBelowTheWindowTop() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let titlebar = EditorWindowController.titlebarHeight(of: window)
        #expect(editor.textView.textContainerOrigin.y == EditorWindowController.topInset - titlebar)
        let top = try #require(editor.firstLineTopFromWindowTop())
        #expect(abs(top - EditorWindowController.topInset) < 0.5)
    }

    @Test func findBarOpensBelowTheTitlebarAndTheTextMovesBelowIt() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let content = try #require(window.contentView)
        let titlebar = EditorWindowController.titlebarHeight(of: window)
        showFindBar(editor)
        let bar = try #require(editor.findBarRect(in: content))
        // Below the titlebar band, where the traffic lights are, not behind it.
        #expect(abs((content.bounds.maxY - bar.maxY) - titlebar) < 0.5)
        let top = try #require(editor.firstLineTopFromWindowTop())
        #expect(abs(top - (EditorWindowController.topInset + bar.height)) < 0.5)
    }

    @Test func updateBarTextStartsBelowTheTitlebar() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let content = try #require(window.contentView)
        editor.showUpdateBar(version: "9.9.9")
        content.layoutSubtreeIfNeeded()
        let bar = try #require(editor.updateBar)
        let label = content.convert(bar.label.bounds, from: bar.label)
        #expect(content.bounds.maxY - label.maxY >= EditorWindowController.titlebarHeight(of: window) - 0.5)
        // The bar itself keeps v2's 48 pt.
        #expect(bar.frame.height == UpdateNoticeBar.height)
    }

    @Test func updateBarIsOpaqueAndTheTextClearsItUntilDismissed() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)
        editor.showUpdateBar(version: "9.9.9")
        content.layoutSubtreeIfNeeded()
        let bar = try #require(editor.updateBar)
        #expect(bar.backgroundColor.alphaComponent == 1)
        bar.setHoveredForTesting(true)
        #expect(bar.backgroundColor.alphaComponent == 1)
        let barBottom = bar.frame.height
        let shown = try #require(editor.firstLineTopFromWindowTop())
        #expect(shown >= barBottom - 0.5)
        #expect(editor.debugDismissUpdate())
        content.layoutSubtreeIfNeeded()
        let after = try #require(editor.firstLineTopFromWindowTop())
        #expect(abs(after - EditorWindowController.topInset) < 0.5)
    }

    @Test func goToLineFieldStartsBelowTheTitlebar() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let content = try #require(window.contentView)
        editor.showGoToLine(nil)
        content.layoutSubtreeIfNeeded()
        let bar = try #require(content.subviews.compactMap { $0 as? GoToLineBar }.first)
        let field = content.convert(bar.field.bounds, from: bar.field)
        #expect(content.bounds.maxY - field.maxY >= EditorWindowController.titlebarHeight(of: window) - 0.5)
    }

    // MARK: Update bar gives way to the find bar and go-to strip

    @Test func goToLineStripReplacesTheUpdateBarUntilClosed() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)
        editor.showUpdateBar(version: "9.9.9")
        content.layoutSubtreeIfNeeded()
        let bar = try #require(editor.updateBar)
        #expect(!bar.isHidden && !editor.isUpdateBarSuppressed)
        let shown = try #require(editor.firstLineTopFromWindowTop())
        #expect(shown >= UpdateNoticeBar.height - 0.5)

        editor.showGoToLine(nil)
        content.layoutSubtreeIfNeeded()
        let strip = try #require(content.subviews.compactMap { $0 as? GoToLineBar }.first)
        #expect(bar.isHidden && editor.isUpdateBarSuppressed)
        #expect(editor.updateBar === bar)
        #expect(isInside(try hit(editor, fromTop: 10), strip))
        let withStrip = try #require(editor.firstLineTopFromWindowTop())
        #expect(abs(withStrip - EditorWindowController.topInset) < 0.5)

        strip.close(restoreFocus: true)
        content.layoutSubtreeIfNeeded()
        #expect(!bar.isHidden && !editor.isUpdateBarSuppressed)
        #expect(isInside(try hit(editor, fromTop: 10), bar))
        let restored = try #require(editor.firstLineTopFromWindowTop())
        #expect(restored >= UpdateNoticeBar.height - 0.5)
    }

    @Test func findBarReplacesTheUpdateBarUntilClosed() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)
        editor.showUpdateBar(version: "9.9.9")
        let bar = try #require(editor.updateBar)

        showFindBar(editor)
        let find = try #require(editor.findBarRect(in: content))
        #expect(bar.isHidden && editor.isUpdateBarSuppressed)
        let withFind = try #require(editor.firstLineTopFromWindowTop())
        #expect(abs(withFind - (EditorWindowController.topInset + find.height)) < 0.5)

        editor.scrollView.isFindBarVisible = false
        content.layoutSubtreeIfNeeded()
        #expect(!bar.isHidden && !editor.isUpdateBarSuppressed)
        let restored = try #require(editor.firstLineTopFromWindowTop())
        #expect(restored >= UpdateNoticeBar.height - 0.5)
    }

    @Test func updateBarStaysHiddenUntilBothTopBarsCloseAndIsNeverDismissedByThem() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)
        let before = editor.model.settings.hiddenUpdateVersion
        editor.showUpdateBar(version: "9.9.9")
        let bar = try #require(editor.updateBar)
        showFindBar(editor)
        editor.showGoToLine(nil)
        editor.scrollView.isFindBarVisible = false
        #expect(bar.isHidden)
        let strip = try #require(content.subviews.compactMap { $0 as? GoToLineBar }.first)
        strip.close(restoreFocus: true)
        #expect(!bar.isHidden)
        #expect(editor.model.settings.hiddenUpdateVersion == before)
    }

    @Test func updateBarShownWhileATopBarIsOpenStartsHidden() throws {
        let editor = try makeEditor()
        editor.showGoToLine(nil)
        editor.showUpdateBar(version: "9.9.9")
        #expect(try #require(editor.updateBar).isHidden)
    }

    // MARK: Drag strip

    @Test func dragStripSpansTheTopOfTheWindow() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)
        let strip = editor.dragStrip
        #expect(strip.superview === content)
        #expect(strip.frame.height == TitlebarDragView.height)
        #expect(TitlebarDragView.height == 40)
        #expect(TitlebarDragView.height < EditorWindowController.topInset)
        #expect(strip.frame.minX == 0 && strip.frame.width == content.bounds.width)
        #expect(strip.frame.maxY == content.bounds.maxY)
        // Above the text in the hierarchy.
        let index = { (view: NSView) in content.subviews.firstIndex { $0 === view } ?? -1 }
        #expect(index(strip) > index(editor.scrollView))
        // It follows the window's width.
        editor.window?.setContentSize(NSSize(width: 700, height: 500))
        #expect(strip.frame.width == content.bounds.width)
        #expect(strip.frame.maxY == content.bounds.maxY)
    }

    @Test func dragStripTakesClicksBelowTheTitlebarButNotTheTextBelowIt() throws {
        let editor = try makeEditor()
        #expect(try hit(editor, fromTop: 35) === editor.dragStrip)
        #expect(try hit(editor, fromTop: TitlebarDragView.height + 5) === editor.textView)
    }

    @Test func dragStripLeavesTheTrafficLightsAlone() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(kind))
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let frame = try #require(window.contentView?.superview)
            #expect(isInside(frame.hitTest(center), button), "\(kind) is covered")
        }
    }

    @Test func dragStripLeavesTheBarsTheirClicks() throws {
        let editor = try makeEditor()
        let content = try #require(editor.window?.contentView)

        showFindBar(editor)
        let find = try #require(editor.findBarRect(in: content))
        let findHit = try hit(editor, fromTop: content.bounds.maxY - find.midY)
        #expect(findHit !== editor.dragStrip)
        #expect(isInside(findHit, try #require(editor.scrollView.findBarView)))

        // The update bar gives way to the find bar, so check it once the find bar is closed.
        editor.scrollView.isFindBarVisible = false
        editor.showUpdateBar(version: "9.9.9")
        content.layoutSubtreeIfNeeded()
        let update = try #require(editor.updateBar)
        #expect(isInside(try hit(editor, fromTop: 10), update))
        #expect(isInside(try hit(editor, fromTop: 35), update))

        editor.showGoToLine(nil)
        content.layoutSubtreeIfNeeded()
        let goToLine = try #require(content.subviews.compactMap { $0 as? GoToLineBar }.first)
        #expect(isInside(try hit(editor, fromTop: 10), goToLine))
        #expect(isInside(try hit(editor, fromTop: 35), goToLine))
    }

    @Test func doubleClickRunsTheSystemAction() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        var asked = 0
        editor.dragStrip.doubleClickAction = {
            asked += 1
            return .none
        }
        let point = editor.dragStrip.convert(NSPoint(x: 50, y: 20), to: nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        editor.dragStrip.mouseDown(with: event)
        #expect(asked == 1)
    }

    @Test func doubleClickActionFollowsTheSystemSetting() {
        #expect(TitlebarDoubleClickAction.resolve(action: nil, miniaturize: false) == .zoom)
        #expect(TitlebarDoubleClickAction.resolve(action: nil, miniaturize: true) == .minimize)
        #expect(TitlebarDoubleClickAction.resolve(action: "Maximize", miniaturize: true) == .zoom)
        #expect(TitlebarDoubleClickAction.resolve(action: "Fill", miniaturize: false) == .zoom)
        #expect(TitlebarDoubleClickAction.resolve(action: "Minimize", miniaturize: false) == .minimize)
        #expect(TitlebarDoubleClickAction.resolve(action: "None", miniaturize: true) == .none)
    }

    // MARK: Full screen

    /// Installed as the app's menu, where AppKit adjusts the full-screen item: one visible item,
    /// and ⌃⌘F still answering through the responder chain to the editor window.
    @Test func fullScreenItemIsSingleAndKeepsControlCommandF() throws {
        let editor = try makeEditor()
        let window = try #require(editor.window)
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        app.mainMenu = MainMenu.build(from: Commands.defaults)

        let view = try #require(app.mainMenu?.item(withTitle: "View")?.submenu)
        let items = view.items.filter { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        #expect(items.filter { !$0.isHidden }.count == 1)
        let controlCommandF = items.filter {
            $0.keyEquivalent == "f" && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.control, .command]
        }
        #expect(controlCommandF.count == 1)
        // AppKit enables the item only in an app that may own a full-screen space; this test
        // process is not one (activation policy .prohibited, measured), so validateUserInterfaceItem
        // is false here whatever the window. What the window controls is checked instead; the
        // enabled state in the app is in the debug menu log (manual-fix-report.md).
        #expect(window.styleMask.contains(.resizable))
        #expect(!window.collectionBehavior.contains(.fullScreenNone))
        if let item = controlCommandF.first {
            #expect(!item.isHidden || item.allowsKeyEquivalentWhenHidden)
            #expect(item.target == nil)
            #expect(window.responds(to: #selector(NSWindow.toggleFullScreen(_:))))
        }
        // No other menu claims ⌃⌘F.
        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(all) ?? []) } }
        let claims = all(try #require(app.mainMenu)).filter {
            $0.keyEquivalent.lowercased() == "f"
                && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.control, .command]
        }
        #expect(claims.count == 1)
    }
}

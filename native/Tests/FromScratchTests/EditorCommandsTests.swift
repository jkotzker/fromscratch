import AppKit
import FromScratchCore
import Testing
@testable import FromScratch

/// Gives the window (and so the text view) an undo manager; a bare window has none in a test.
@MainActor
private final class UndoProvider: NSObject, NSWindowDelegate {
    let undoManager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }
}

/// A TextKit 2 editor in an offscreen window, set up the way the window controller does it.
@MainActor
private final class Harness {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: true)
    let textView = EditorTextView(usingTextLayoutManager: true)
    let undo = UndoProvider()
    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    init(_ text: String, selection: [NSRange] = [NSRange(location: 0, length: 0)]) {
        _ = NSApplication.shared
        window.delegate = undo
        textView.configureForPlainText()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.contentView = textView
        textView.font = font
        textView.typingAttributes[.font] = font
        textView.string = text
        textView.selectedRanges = selection.map { NSValue(range: $0) }
        window.makeFirstResponder(textView)
    }

    var undoManager: UndoManager { undo.undoManager }
}

private func range(_ location: Int, _ length: Int = 0) -> NSRange { NSRange(location: location, length: length) }

@MainActor
struct EditorCommandsTests {
    init() { silenceFeedback() }

    @Test func checkboxOverSeveralLinesIsOneNamedUndoStep() {
        let h = Harness("a\nb\nc", selection: [range(0, 5)])
        h.textView.toggleCheckbox(nil)
        #expect(h.textView.string == "[ ] a\n[ ] b\n[ ] c")
        #expect(h.undoManager.undoActionName == "Toggle Checkbox")
        h.undoManager.undo()
        #expect(h.textView.string == "a\nb\nc")
        #expect(!h.undoManager.canUndo)
        h.undoManager.redo()
        #expect(h.textView.string == "[ ] a\n[ ] b\n[ ] c")
        #expect(h.textView.textLayoutManager != nil, "a command switched the view to TextKit 1")
    }

    @Test func moveAndDeleteKeepSelectionAndUndo() {
        let h = Harness("one\ntwo\nthree", selection: [range(1)])
        h.textView.moveLineDown(nil)
        #expect(h.textView.string == "two\none\nthree")
        #expect(h.textView.selectedRange() == range(5))
        #expect(h.undoManager.undoActionName == "Move Line Down")
        h.textView.moveLineUp(nil)
        #expect(h.textView.string == "one\ntwo\nthree")
        h.textView.deleteLine(nil)
        #expect(h.textView.string == "two\nthree")
        #expect(h.undoManager.undoActionName == "Delete Line")
        // Each command is its own undo step, even with no run loop closing event groups.
        h.undoManager.undo()
        #expect(h.textView.string == "one\ntwo\nthree")
        #expect(h.undoManager.undoActionName == "Move Line Up")
        h.undoManager.undo()
        #expect(h.textView.string == "two\none\nthree")
        #expect(h.undoManager.undoActionName == "Move Line Down")
        h.undoManager.undo()
        #expect(h.textView.string == "one\ntwo\nthree")
        #expect(!h.undoManager.canUndo)
        #expect(h.undoManager.groupsByEvent, "the command left groupsByEvent switched off")
    }

    @Test func readOnlyNoteIsNeverChanged() {
        let h = Harness("a\nb")
        h.textView.isEditable = false
        for action in [#selector(EditorTextView.toggleCheckbox(_:)), #selector(EditorTextView.deleteLine(_:)),
                       #selector(EditorTextView.moveLineDown(_:)), #selector(EditorTextView.moveLineUp(_:))] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            #expect(!h.textView.validateUserInterfaceItem(item), "\(action) is enabled on a read-only note")
        }
        // Even sent directly, nothing changes and nothing is recorded; each one beeps instead.
        #expect(beeps { h.textView.toggleCheckbox(nil) } == 1)
        #expect(beeps { h.textView.deleteLine(nil) } == 1)
        #expect(beeps { h.textView.insertTab(nil) } == 1)
        #expect(beeps { h.textView.insertNewline(nil) } == 1)
        #expect(h.textView.string == "a\nb")
        #expect(h.window.firstResponder === h.textView, "Return gave up focus in a read-only note")
        #expect(!h.undoManager.canUndo)
    }

    @Test func insertedTextGetsTheEditorAttributesInAnEmptyNote() {
        let h = Harness("")
        h.textView.toggleCheckbox(nil)
        #expect(h.textView.string == "[ ] ")
        let storage = h.textView.textContentStorage?.textStorage
        #expect(storage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == h.font)
    }

    @Test func deleteLineOnAnEmptyNoteRecordsNothing() {
        let h = Harness("")
        h.textView.deleteLine(nil)
        #expect(!h.undoManager.canUndo)
    }

    @Test func returnKeepsTheLineIndent() {
        let h = Harness("\tfoo", selection: [range(4)])
        h.undoManager.beginUndoGrouping()  // typing needs an open group outside an event loop
        h.textView.insertNewline(nil)
        h.undoManager.endUndoGrouping()
        #expect(h.textView.string == "\tfoo\n\t")
        #expect(h.textView.selectedRange() == range(6))
    }

    @Test func tabDuringCompositionIsLeftToTheTextSystem() {
        let h = Harness("a", selection: [range(1)])
        h.textView.setMarkedText("k", selectedRange: range(1), replacementRange: range(1))
        #expect(h.textView.hasMarkedText())
        h.undoManager.beginUndoGrouping()  // typing needs an open group outside an event loop
        h.textView.insertTab(nil)
        h.textView.insertBacktab(nil)
        h.undoManager.endUndoGrouping()
        #expect(h.undoManager.undoActionName != "Indent")
        #expect(h.undoManager.undoActionName != "Outdent")
    }

    @Test func tabIndentsAndBacktabOutdentsSelectedLines() {
        let h = Harness("a\nb", selection: [range(0, 3)])
        h.textView.insertTab(nil)
        #expect(h.textView.string == "\ta\n\tb")
        #expect(h.undoManager.undoActionName == "Indent")
        h.textView.insertBacktab(nil)
        #expect(h.textView.string == "a\nb")
        // An empty selection inserts a tab character.
        h.textView.selectedRanges = [NSValue(range: range(1))]
        h.textView.insertTab(nil)
        #expect(h.textView.string == "a\t\nb")
    }
}

/// The go-to-line strip and ⌘S, through the real window controller on a temporary data folder.
@MainActor
struct EditorWindowCommandsTests {
    init() { silenceFeedback() }

    private func makeController(text: String) throws -> (EditorWindowController, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FromScratchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(ContentStore.fileName))
        let controller = EditorWindowController(model: AppModel(dataDirectory: directory))
        controller.window?.makeFirstResponder(controller.textView)
        return (controller, directory)
    }

    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: keyCode)!
        window.sendEvent(event)
    }

    @Test func returnInTheStripMovesTheCaretAndClosesIt() throws {
        let (controller, _) = try makeController(text: "one\ntwo\nthree")
        let window = try #require(controller.window)
        controller.textView.setSelectedRange(range(5))
        controller.showGoToLine(nil)
        #expect(controller.isGoToLineOpen)
        // Pre-filled with the caret's line, selected so typing replaces it.
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.string == "2")
        #expect(editor.selectedRange() == range(0, 1))
        editor.insertText("3:2", replacementRange: editor.selectedRange())
        press("\r", keyCode: 36, in: window)
        #expect(!controller.isGoToLineOpen)
        #expect(controller.textView.selectedRange() == range(9))
        #expect(window.firstResponder === controller.textView)
    }

    @Test func escClosesTheStripAndReturnsFocus() throws {
        let (controller, _) = try makeController(text: "one\ntwo")
        let window = try #require(controller.window)
        controller.textView.setSelectedRange(range(2))
        controller.showGoToLine(nil)
        press("\u{1b}", keyCode: 53, in: window)
        #expect(!controller.isGoToLineOpen)
        #expect(window.firstResponder === controller.textView)
        // Cancelling leaves the caret where it was.
        #expect(controller.textView.selectedRange() == range(2))
    }

    @Test func invalidInputKeepsTheStripOpen() throws {
        let (controller, _) = try makeController(text: "one")
        let window = try #require(controller.window)
        controller.showGoToLine(nil)
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("x", replacementRange: editor.selectedRange())
        #expect(beeps { press("\r", keyCode: 36, in: window) } == 1)
        #expect(controller.isGoToLineOpen)
    }

    @Test func goToLinePressedTwiceKeepsTheStripFocused() throws {
        let (controller, _) = try makeController(text: "one\ntwo")
        let window = try #require(controller.window)
        controller.textView.setSelectedRange(range(0))
        controller.showGoToLine(nil)
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("9", replacementRange: editor.selectedRange())
        controller.showGoToLine(nil)
        #expect(controller.isGoToLineOpen)
        let again = try #require(window.firstResponder as? NSTextView, "nothing has focus")
        #expect(again !== controller.textView)
        // Re-filled with the caret's line and selected, as on first open.
        #expect(again.string == "1")
        #expect(again.selectedRange() == range(0, 1))
    }

    /// Closing without committing leaves the scroll position alone, so the click that moved focus
    /// lands on the text that was under the pointer.
    @Test func losingFocusDoesNotScroll() throws {
        let text = (1...300).map { "line \($0)" }.joined(separator: "\n")
        let (controller, _) = try makeController(text: text)
        let window = try #require(controller.window)
        let clip = try #require(controller.textView.enclosingScrollView?.contentView)
        controller.textView.setSelectedRange(range(0))
        controller.textView.scrollRangeToVisible(range((text as NSString).length))
        let scrolled = clip.bounds.origin
        #expect(scrolled.y > 0, "the test needs the caret off screen")
        controller.showGoToLine(nil)
        window.makeFirstResponder(controller.textView)
        #expect(!controller.isGoToLineOpen)
        #expect(clip.bounds.origin == scrolled)
    }

    @Test func focusLeavingTheStripClosesIt() throws {
        let (controller, _) = try makeController(text: "one")
        let window = try #require(controller.window)
        controller.showGoToLine(nil)
        window.makeFirstResponder(controller.textView)
        #expect(!controller.isGoToLineOpen)
    }

    @Test func saveNowWritesPendingTextAndShowsTheHint() throws {
        let (controller, directory) = try makeController(text: "old")
        controller.textView.setSelectedRange(range(3))
        controller.textView.insertText("er", replacementRange: controller.textView.selectedRange())
        controller.saveNow(nil)
        let saved = try String(contentsOf: directory.appendingPathComponent(ContentStore.fileName), encoding: .utf8)
        #expect(saved == "older")
        let notices = controller.window?.contentView?.subviews.compactMap { ($0 as? OverlayNotice)?.text }
        #expect(notices == [EditorWindowController.savedNotice])
        // Pressed again while it is up, the same notice stays (its timer restarts).
        controller.saveNow(nil)
        #expect(controller.window?.contentView?.subviews.compactMap { $0 as? OverlayNotice }.count == 1)
    }

    @Test func commandEditsReachTheContentStore() throws {
        let (controller, directory) = try makeController(text: "task")
        controller.textView.toggleCheckbox(nil)
        controller.saveNow(nil)
        let saved = try String(contentsOf: directory.appendingPathComponent(ContentStore.fileName), encoding: .utf8)
        #expect(saved == "[ ] task")
    }

    @Test func lineNumbers() {
        let text = "a\nb\n" as NSString
        #expect(EditorWindowController.lineNumber(at: 0, in: text) == 1)
        #expect(EditorWindowController.lineNumber(at: 1, in: text) == 1)
        #expect(EditorWindowController.lineNumber(at: 2, in: text) == 2)
        #expect(EditorWindowController.lineNumber(at: 4, in: text) == 3)
        #expect(EditorWindowController.lineNumber(at: 0, in: "" as NSString) == 1)
        #expect(EditorWindowController.lineNumber(at: 3, in: "a\r\nb" as NSString) == 2)
    }
}

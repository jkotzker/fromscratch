import AppKit
#if DEBUG
import CryptoKit
#endif
import FromScratchCore
import Testing
@testable import FromScratch

/// Closing the editor, window restoration and the debug state line, through the real window
/// controller and app delegate on a temporary data folder. Nothing here terminates the test run:
/// the delegate's termination request is replaced with a counter.
@MainActor
@Suite(.serialized)
struct WindowLifecycleTests {
    /// attach(model:) makes the font controller the font manager's target, which the manager does
    /// not clear when it is freed; keeping the delegates alive keeps that target valid.
    private static var delegates: [AppDelegate] = []

    private func dataFolder(text: String) throws -> URL {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FromScratchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(ContentStore.fileName))
        return directory
    }

    /// Runs the main run loop in the default mode, where the delegate schedules its request.
    private func spin(until condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    @Test func closingTheEditorWithAnotherWindowOpenRequestsTermination() throws {
        let model = AppModel(dataDirectory: try dataFolder(text: "note"))
        let delegate = AppDelegate()
        Self.delegates.append(delegate)
        delegate.attach(model: model)
        var requests = 0
        delegate.requestTermination = { requests += 1 }
        let editor = EditorWindowController(model: model)
        delegate.install(editor: editor)

        // A second visible window, as Settings or the font panel would be. Borderless and far
        // off screen so the test shows nothing.
        let other = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 10, height: 10),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderBack(nil)
        defer { other.orderOut(nil) }
        #expect(other.isVisible)

        // AppKit's last-window rule is off, so the editor's own close is the only path to a quit.
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))

        editor.window?.close()
        // Scheduled on the run loop, not made from inside the close.
        #expect(requests == 0)
        spin(until: { requests > 0 })
        #expect(requests == 1)
        // Nothing asks a second time.
        spin(until: { requests > 1 }, timeout: 0.3)
        #expect(requests == 1)
    }

    @Test func editorWindowIsNotRestorable() throws {
        let editor = EditorWindowController(model: AppModel(dataDirectory: try dataFolder(text: "")))
        #expect(editor.window?.isRestorable == false)
    }

    #if DEBUG
    @Test func debugStateNeverContainsTheNoteText() throws {
        let text = "private note ✓"
        let editor = EditorWindowController(model: AppModel(dataDirectory: try dataFolder(text: text)))
        let state = editor.debugState()
        #expect(!state.contains("private"))
        #expect(!state.contains("text="))
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(state.contains("textLength=\((text as NSString).length) "))
        #expect(state.contains("textSHA256=\(digest.prefix(16)) "))
    }
    #endif
}

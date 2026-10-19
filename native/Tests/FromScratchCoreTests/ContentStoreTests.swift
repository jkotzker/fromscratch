import Foundation
import Testing
@testable import FromScratchCore

@MainActor
struct ContentStoreTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fs-content-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ dir: URL) -> URL { dir.appendingPathComponent("content.txt") }
    func put(_ dir: URL, _ bytes: [UInt8]) { try! Data(bytes).write(to: file(dir)) }
    func disk(_ dir: URL) -> Data { try! Data(contentsOf: file(dir)) }

    @Test func missingFileGivesEmptyText() {
        let dir = tempDir()
        let store = ContentStore(directory: dir)
        #expect(store.initialText == "")
        #expect(!store.isReadOnly)
        store.scheduleWrite("hi")
        store.flush()
        #expect(disk(dir) == Data("hi".utf8))
    }

    @Test func roundTripIsByteIdentical() {
        let dir = tempDir()
        let bytes = Array("a\r\nb\tc 👋🏽 é\u{301}".utf8)
        put(dir, bytes)
        let store = ContentStore(directory: dir)
        store.scheduleWrite(store.initialText)
        store.flush()
        #expect(disk(dir) == Data(bytes))
    }

    @Test func flushWritesPendingText() {
        let dir = tempDir()
        let store = ContentStore(directory: dir)
        store.scheduleWrite("x")
        #expect(store.hasPendingWrite)
        store.flush()
        #expect(disk(dir) == Data("x".utf8))
        #expect(!store.hasPendingWrite)
    }

    @Test func debouncedWriteLandsAfterDelay() async throws {
        let dir = tempDir()
        let store = ContentStore(directory: dir, debounce: .milliseconds(20))
        store.scheduleWrite("one")
        store.scheduleWrite("two")
        try await Task.sleep(for: .milliseconds(150))
        #expect(disk(dir) == Data("two".utf8))
        #expect(!store.hasPendingWrite)
    }

    @Test func invalidUTF8IsReadOnlyAndNeverOverwritten() {
        let dir = tempDir()
        put(dir, [0xff, 0xfe, 0x41])
        let store = ContentStore(directory: dir)
        #expect(store.isReadOnly)
        #expect(store.initialText.contains("A"))
        store.scheduleWrite("new")
        #expect(!store.hasPendingWrite)
        store.flush()
        #expect(disk(dir) == Data([0xff, 0xfe, 0x41]))
        #expect(store.suddenTerminationBalance == 0)
    }

    @Test func writeIsAtomic() {
        let dir = tempDir()
        let store = ContentStore(directory: dir)
        store.scheduleWrite("abc")
        store.flush()
        let names = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["content.txt"])
    }

    @Test func suddenTerminationStaysBalanced() async throws {
        let dir = tempDir()
        let store = ContentStore(directory: dir, debounce: .milliseconds(20))
        #expect(store.suddenTerminationBalance == 0)
        store.scheduleWrite("a")
        store.scheduleWrite("b")      // superseded text must not disable a second time
        #expect(store.suddenTerminationBalance == 1)
        store.flush()
        #expect(store.suddenTerminationBalance == 0)
        store.flush()                  // nothing pending: no extra enable
        #expect(store.suddenTerminationBalance == 0)
        store.scheduleWrite("c")
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.suddenTerminationBalance == 0)
        #expect(disk(dir) == Data("c".utf8))
    }

    @Test func failedWriteStaysPendingAndRetries() {
        let dir = tempDir()
        let store = ContentStore(directory: dir)
        // A directory at the target path makes the atomic rename fail.
        try! FileManager.default.createDirectory(at: file(dir), withIntermediateDirectories: true)
        store.scheduleWrite("keep")
        store.flush()
        #expect(store.hasPendingWrite)
        #expect(store.lastWriteError != nil)
        #expect(store.suddenTerminationBalance == 1)
        try! FileManager.default.removeItem(at: file(dir))
        store.flush()
        #expect(!store.hasPendingWrite)
        #expect(store.lastWriteError == nil)
        #expect(store.suddenTerminationBalance == 0)
        #expect(disk(dir) == Data("keep".utf8))
    }
}

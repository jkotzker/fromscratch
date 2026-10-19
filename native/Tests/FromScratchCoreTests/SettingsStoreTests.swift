import Foundation
import Testing
@testable import FromScratchCore

@MainActor
struct SettingsStoreTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fs-settings-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func put(_ dir: URL, _ name: String, _ text: String) {
        try! text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func disk(_ dir: URL) -> [String: JSONValue] {
        let d = try! Data(contentsOf: dir.appendingPathComponent("settings.json"))
        return try! JSONDecoder().decode([String: JSONValue].self, from: d)
    }

    let v2File = """
    {"version":1,"font":{"family":"Menlo","size":18},"colorScheme":"built-in:light",
     "highlightCurrentLine":false,
     "windowstate":{"bounds":{"x":10,"y":20,"width":550,"height":400},"isMaximized":true},
     "hideUpdateMessage":{"version":"2.2.0"},"folds2":{"a":[1,2,{"b":null}]}}
    """

    @Test func loadsV2File() {
        let dir = tempDir(); put(dir, "settings.json", v2File)
        let s = SettingsStore(directory: dir)
        #expect(s.font == FontSetting(family: "Menlo", size: 18))
        #expect(s.colorSchemeId == "built-in:light")
        #expect(s.highlightCurrentLine == false)
        #expect(s.windowState == WindowState(bounds: CGRect(x: 10, y: 20, width: 550, height: 400), isMaximized: true))
        #expect(s.hiddenUpdateVersion == "2.2.0")
    }

    @Test func unknownKeysSurviveSave() {
        let dir = tempDir()
        put(dir, "settings.json", v2File.replacingOccurrences(of: "\"folds2\"", with: "\"zzz\":[true,1.5,\"x\"],\"folds2\""))
        let before = disk(dir)
        let s = SettingsStore(directory: dir)
        s.highlightCurrentLine = true
        s.flush()
        let after = disk(dir)
        #expect(after["folds2"] == before["folds2"])
        #expect(after["zzz"] == before["zzz"])
        #expect(after["highlightCurrentLine"] == .bool(true))
    }

    @Test func wrongTypesFallBackAndSurvive() {
        let dir = tempDir()
        put(dir, "settings.json", #"{"font":{"family":"Menlo","size":"big"},"windowstate":null,"colorScheme":5,"keep":1}"#)
        let s = SettingsStore(directory: dir)
        #expect(s.font.size == 16)
        #expect(s.windowState.bounds == nil && s.windowState.isMaximized == false)
        #expect(s.colorSchemeId == "built-in:dark")
        s.highlightCurrentLine = false
        s.flush()
        let d = disk(dir)
        #expect(d["windowstate"] == JSONValue.null)
        #expect(d["colorScheme"] == .number(5))
        #expect(d["font"]?.objectValue?["size"] == .string("big"))
        #expect(d["keep"] == .number(1))
    }

    @Test func corruptFileIsKeptAside() throws {
        let dir = tempDir(); put(dir, "settings.json", "{not json")
        _ = SettingsStore(directory: dir)
        let kept = try String(contentsOf: dir.appendingPathComponent("settings.json.corrupt"), encoding: .utf8)
        #expect(kept == "{not json")
        #expect(disk(dir)["version"] == .number(1))
    }

    @Test func migratesLegacyWhenNoSettingsJson() {
        let dir = tempDir()
        put(dir, "fontSize", "1.25"); put(dir, "lightTheme", "true")
        put(dir, "windowstate", #"{"bounds":{"x":1,"y":2,"width":3,"height":4},"isMaximized":false}"#)
        put(dir, "folds2", #"{"f":[1]}"#); put(dir, "hideUpdateMessage", #"{"version":"2.0.0"}"#)
        let s = SettingsStore(directory: dir)
        #expect(s.font.size == 20)
        #expect(s.colorSchemeId == "built-in:light")
        #expect(s.raw["folds2"] == .object(["f": .array([.number(1)])]))
        #expect(s.hiddenUpdateVersion == "2.0.0")
        #expect(s.windowState.bounds == CGRect(x: 1, y: 2, width: 3, height: 4))
        for n in SettingsStore.legacyKeys {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path))
        }
    }

    @Test func doesNotMigrateWhenSettingsJsonExists() {
        let dir = tempDir()
        put(dir, "settings.json", #"{"version":1}"#); put(dir, "fontSize", "2"); put(dir, "lightTheme", "true")
        let s = SettingsStore(directory: dir)
        #expect(s.font.size == 16)
        #expect(s.colorSchemeId == "built-in:dark")
    }

    @Test func fontSizeRoundedAndClamped() {
        let dir = tempDir()
        let s = SettingsStore(directory: dir)
        for (input, expected) in [(13.6, 14), (200.0, 72), (3.0, 8)] {
            var f = s.font
            f.size = FontSetting.clamp(input)
            s.font = f
            s.flush()
            #expect(disk(dir)["font"]?.objectValue?["size"] == .number(Double(expected)))
        }
    }

    @Test func fontFaceIsSeparateKey() {
        let dir = tempDir()
        let s = SettingsStore(directory: dir)
        s.font = FontSetting(family: "Menlo", size: 14, face: "Menlo-Bold")
        s.flush()
        let d = disk(dir)
        #expect(d["fontFace"] == .string("Menlo-Bold"))
        #expect(d["font"] == .object(["family": .string("Menlo"), "size": .number(14)]))
        s.font = FontSetting(family: "Menlo", size: 14)
        s.flush()
        #expect(disk(dir)["fontFace"] == nil)
    }

    @Test func debouncedWriteAndFlushCancels() async throws {
        let dir = tempDir()
        let s = SettingsStore(directory: dir, debounce: .milliseconds(30))
        s.colorSchemeId = "built-in:light"
        #expect(disk(dir)["colorScheme"] == nil)
        try await eventually { disk(dir)["colorScheme"] != nil }
        #expect(disk(dir)["colorScheme"] == .string("built-in:light"))
        s.colorSchemeId = "x"; s.flush()
        #expect(disk(dir)["colorScheme"] == .string("x"))
    }

    @Test func wholeNumbersEncodeWithoutFraction() throws {
        let dir = tempDir(); put(dir, "settings.json", v2File)
        // A change is needed: flush writes only what is pending.
        let s = SettingsStore(directory: dir); s.colorSchemeId = "built-in:dark"; s.flush()
        let text = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(text.contains("\"width\" : 550,") && !text.contains("550.0"))
    }

    @Test func secondCorruptionKeepsFirstBackup() throws {
        let dir = tempDir(); put(dir, "settings.json", "{first")
        _ = SettingsStore(directory: dir)
        put(dir, "settings.json", "{second")
        _ = SettingsStore(directory: dir)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let first = try String(contentsOf: dir.appendingPathComponent("settings.json.corrupt"), encoding: .utf8)
        #expect(first == "{first")
        let extra = names.filter { $0.hasPrefix("settings.json.corrupt-") }
        #expect(extra.count == 1)
        let second = try String(contentsOf: dir.appendingPathComponent(extra[0]), encoding: .utf8)
        #expect(second == "{second")
    }

    @Test func failedMoveLeavesOriginalUntouched() throws {
        let dir = tempDir(); put(dir, "settings.json", "{not json")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let s = SettingsStore(directory: dir)
        s.highlightCurrentLine = false
        s.flush()
        #expect(s.highlightCurrentLine == false)
        let kept = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(kept == "{not json")
    }

    @Test func storedFiraCodeReadsAsBundled() {
        let dir = tempDir(); put(dir, "settings.json", #"{"font":{"family":"FiraCode","size":16}}"#)
        #expect(SettingsStore(directory: dir).font.family == nil)
    }

    @Test func setterNormalizesFiraCode() {
        let dir = tempDir()
        let s = SettingsStore(directory: dir)
        var f = FontSetting(); f.family = "FiraCode"
        s.font = f; s.flush()
        #expect(disk(dir)["font"]?.objectValue?["family"] == JSONValue.null)
    }

    // v2's flushSettings returns early with no write pending, so a hand edit made while the app
    // runs survives a quit that changed nothing.
    @Test func flushWithoutChangesLeavesTheFileAlone() throws {
        let dir = tempDir(); put(dir, "settings.json", v2File)
        let url = dir.appendingPathComponent("settings.json")
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        let before = try Data(contentsOf: url)
        let s = SettingsStore(directory: dir)
        s.flush()
        #expect(try Data(contentsOf: url) == before)
        let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(mtime == old)
        // A change after that is still written, and only once.
        s.highlightCurrentLine = true
        s.flush()
        #expect(disk(dir)["highlightCurrentLine"] == .bool(true))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        s.flush()
        let again = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(again == old)
    }

    // v2's writeFileSync followed a symlink; an atomic write must not replace the link with a file.
    @Test func symlinkedSettingsStaysALink() throws {
        let dir = tempDir()
        let elsewhere = tempDir()
        let target = elsewhere.appendingPathComponent("real-settings.json")
        try v2File.write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let s = SettingsStore(directory: dir)
        s.colorSchemeId = "x"
        s.flush()
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        let stored = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: target))
        #expect(stored["colorScheme"] == .string("x"))
        #expect(stored["folds2"] != nil)
    }

    // A read error is not a decode failure: the file may be fine, so it is neither moved aside
    // nor overwritten, and the app runs on defaults.
    @Test func unreadableSettingsIsNotMovedOrOverwritten() throws {
        let dir = tempDir(); put(dir, "settings.json", v2File)
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let s = SettingsStore(directory: dir)
        #expect(s.colorSchemeId == SettingsStore.defaultScheme)
        s.highlightCurrentLine = true
        s.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try String(contentsOf: url, encoding: .utf8) == v2File)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["settings.json"])
    }
}

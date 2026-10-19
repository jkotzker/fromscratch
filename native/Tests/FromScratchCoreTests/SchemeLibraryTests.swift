import Foundation
import Testing
@testable import FromScratchCore

private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
    <key>Background Color</key><dict>
    <key>Red Component</key><real>0.1</real><key>Green Component</key><real>0.2</real><key>Blue Component</key><real>0.3</real>
    </dict>
    <key>Foreground Color</key><dict>
    <key>Red Component</key><real>0.9</real><key>Green Component</key><real>0.8</real><key>Blue Component</key><real>0.7</real>
    </dict>
    </dict></plist>
    """

private func tempThemes() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fs-themes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent(SchemeLibrary.themesDirname)
}

struct SchemeLibraryTests {
    @Test func discoversSortedSkipsBadFiles() throws {
        let dir = try tempThemes()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try sample.write(to: dir.appendingPathComponent("b.itermcolors"), atomically: true, encoding: .utf8)
        try sample.write(to: dir.appendingPathComponent("A.itermcolors"), atomically: true, encoding: .utf8)
        try "<plist><dict></dict></plist>".write(to: dir.appendingPathComponent("bad.itermcolors"), atomically: true, encoding: .utf8)
        try "hi".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let library = SchemeLibrary(themesDirectory: dir)
        #expect(library.all.map(\.name) == ["Dark", "Light", "A", "b"])
        #expect(library.all.dropFirst(2).map(\.id) == ["file:A", "file:b"])
    }

    @Test func createsThemesDirectoryWhenMissing() throws {
        let dir = try tempThemes()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        var isDir: ObjCBool = false
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        _ = SchemeLibrary(themesDirectory: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test func missingIdResolvesToDarkWithoutChangingSetting() throws {
        let dir = try tempThemes()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let library = SchemeLibrary(themesDirectory: dir)
        #expect(library.resolve(id: "file:Gone").id == "built-in:dark")
        #expect(library.resolve(id: "built-in:light").id == "built-in:light")
    }

    @Test func builtInPaletteMatchesDerivationFromHex() {
        for built in [BuiltInScheme.dark, .light] {
            let direct = derivePalette(built.colors)
            let viaScheme = Scheme(builtIn: built).palette
            #expect(viaScheme.background == direct.background)
            #expect(viaScheme.text == direct.text)
            #expect(viaScheme.selection == direct.selection)
            #expect(viaScheme.cursor == direct.cursor)
            #expect(viaScheme.activeLine == direct.activeLine)
            #expect(viaScheme.isDark == direct.isDark)
        }
        #expect(Scheme(builtIn: .dark).isDark)
        #expect(!Scheme(builtIn: .light).isDark)
    }
}

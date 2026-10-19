import Foundation
import Testing
@testable import FromScratchCore

struct PaletteFixture: Decodable, Sendable, CustomTestStringConvertible {
    struct Input: Decodable, Sendable {
        let background: String
        let foreground: String
        let selection: String?
        let selectedText: String?
        let cursor: String?
    }
    let input: Input
    let dark: Bool
    let bg: String
    let text: String
    let bgTranslucent: String
    let bg1Translucent: String
    let selection: String
    let selectedText: String
    let cursor: String
    let overlayBg: String
    let overlayText: String
    let overlayTextHover: String

    enum CodingKeys: String, CodingKey {
        case input, dark
        case bg = "--bg", text = "--text"
        case bgTranslucent = "--bg-translucent", bg1Translucent = "--bg-1-translucent"
        case selection = "--selection", selectedText = "--selected-text", cursor = "--cursor"
        case overlayBg = "--overlay-bg", overlayText = "--overlay-text", overlayTextHover = "--overlay-text-hover"
    }

    var testDescription: String { "\(input.background) on \(input.foreground)" }

    static let all: [PaletteFixture] = {
        let url = Bundle.module.url(forResource: "palette", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([PaletteFixture].self, from: Data(contentsOf: url))
    }()
}

@Suite struct PaletteTests {
    @Test func fixtureHasNineEntries() {
        #expect(PaletteFixture.all.count == 9)
    }

    @Test(arguments: PaletteFixture.all)
    func matchesV2ForEveryFixture(_ f: PaletteFixture) throws {
        let colors = SchemeColors(
            background: try #require(RGB(hex: f.input.background)),
            foreground: try #require(RGB(hex: f.input.foreground)),
            selection: f.input.selection.flatMap { RGB(hex: $0) },
            selectedText: f.input.selectedText.flatMap { RGB(hex: $0) },
            cursor: f.input.cursor.flatMap { RGB(hex: $0) })
        let p = derivePalette(colors)
        #expect(isDark(colors.background) == f.dark)
        #expect(p.isDark == f.dark)
        #expect(p.background.hex == f.bg)
        #expect(p.text.hex == f.text)
        #expect(p.surface.css == f.bgTranslucent)
        #expect(p.activeLine.css == f.bg1Translucent)
        #expect(p.selection.hex == f.selection)
        #expect(p.selectedText.hex == f.selectedText)
        #expect(p.cursor.hex == f.cursor)
        #expect(p.overlayBackground.css == f.overlayBg)
        #expect(p.overlayText.css == f.overlayText)
        #expect(p.overlayTextHover.css == f.overlayTextHover)
    }

    @Test func hexParsing() {
        #expect(RGB(hex: "#abc")?.hex == "#aabbcc")
        #expect(RGB(hex: "002B36")?.hex == "#002b36")
        #expect(RGB(hex: "#12") == nil)
        #expect(RGB(hex: "#gggggg") == nil)
    }

    @Test func alphaFormatting() {
        let c = RGB(r: 1, g: 2, b: 3)
        #expect(RGBA(rgb: c, alpha: 0).css == "rgba(1, 2, 3, 0)")
        #expect(RGBA(rgb: c, alpha: 1).css == "rgba(1, 2, 3, 1)")
        #expect(RGBA(rgb: c, alpha: 0.85).css == "rgba(1, 2, 3, 0.85)")
        #expect(RGBA(rgb: c, alpha: 0.8049999999999999).css == "rgba(1, 2, 3, 0.805)")
    }

    @Test func builtIns() {
        #expect(BuiltInScheme.dark.id == "built-in:dark")
        #expect(BuiltInScheme.light.name == "Light")
        #expect(BuiltInScheme.dark.colors.background.hex == "#002b36")
        #expect(BuiltInScheme.light.colors.foreground.hex == "#657b83")
    }
}

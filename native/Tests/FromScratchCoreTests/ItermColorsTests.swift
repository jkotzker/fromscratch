import Foundation
import Testing
@testable import FromScratchCore

private func colorDict(_ name: String, r: String, g: String, b: String, space: String? = nil) -> String {
    let spaceXML = space.map { "<key>Color Space</key><string>\($0)</string>" } ?? ""
    return """
        <key>\(name)</key><dict>
        \(spaceXML)
        <key>Red Component</key>\(r)
        <key>Green Component</key>\(g)
        <key>Blue Component</key>\(b)
        <key>Alpha Component</key><real>1</real>
        </dict>
        """
}

private func plist(_ entries: [String]) -> Data {
    Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        \(entries.joined(separator: "\n"))
        </dict></plist>
        """.utf8)
}

struct ItermColorsTests {
    @Test func parsesSRGBP3AndUndeclared() throws {
        let data = plist([
            colorDict("Background Color", r: "<real>0.5</real>", g: "<integer>0</integer>", b: "<integer>1</integer>", space: "P3"),
            colorDict("Foreground Color", r: "<real>0.1</real>", g: "<real>0.2</real>", b: "<real>0.3</real>", space: "sRGB"),
            colorDict("Cursor Color", r: "<real>0.4</real>", g: "<real>0.5</real>", b: "<real>0.6</real>"),
        ])
        let parsed = try #require(parseItermColors(data))
        #expect(parsed.background == DeclaredColor(space: .displayP3, r: 0.5, g: 0, b: 1))
        #expect(parsed.foreground == DeclaredColor(space: .sRGB, r: 0.1, g: 0.2, b: 0.3))
        #expect(parsed.cursor == DeclaredColor(space: .sRGB, r: 0.4, g: 0.5, b: 0.6))
    }

    @Test func missingBackgroundOrForegroundReturnsNil() {
        let c = { (n: String) in colorDict(n, r: "<real>0</real>", g: "<real>0</real>", b: "<real>0</real>") }
        #expect(parseItermColors(plist([c("Foreground Color")])) == nil)
        #expect(parseItermColors(plist([c("Background Color")])) == nil)
        #expect(parseItermColors(Data("not a plist".utf8)) == nil)
    }

    @Test func optionalColoursAreNilWhenAbsent() throws {
        let z = "<real>0</real>"
        let parsed = try #require(parseItermColors(plist([
            colorDict("Background Color", r: z, g: z, b: z),
            colorDict("Foreground Color", r: z, g: z, b: z),
        ])))
        #expect(parsed.selection == nil)
        #expect(parsed.selectedText == nil)
        #expect(parsed.cursor == nil)
    }

    @Test func p3ConvertsToSRGBForDerivation() {
        let red = DeclaredColor(space: .displayP3, r: 1, g: 0, b: 0).sRGBForDerivation
        #expect(red == RGB(r: 255, g: 0, b: 0))
    }

    // Expected values were computed outside the code under test: Display P3 decode (sRGB transfer
    // function), linear P3 -> XYZ D65 -> linear sRGB matrices, sRGB encode, clamp, round (Python).
    @Test func p3MidGamutColourIsConverted() {
        let p3 = DeclaredColor(space: .displayP3, r: 0.8, g: 0.4, b: 0.2).sRGBForDerivation
        #expect(p3 != DeclaredColor(space: .sRGB, r: 0.8, g: 0.4, b: 0.2).sRGBForDerivation)
        #expect(p3 == RGB(r: 219, g: 94, b: 31))
    }

    @Test func p3NeutralGreyStaysGrey() {
        // Same transfer function and white point: grey maps to grey (within matrix rounding of 1).
        let grey = DeclaredColor(space: .displayP3, r: 0.5, g: 0.5, b: 0.5).sRGBForDerivation
        for c in [grey.r, grey.g, grey.b] { #expect(abs(Int(c) - 128) <= 1) }
    }

    @Test func srgbQuantizesLikeV2() {
        // sRGB quantizes like v2's hex conversion (Math.round half away from zero).
        #expect(DeclaredColor(space: .sRGB, r: 0.5, g: 2, b: -1).sRGBForDerivation == RGB(r: 128, g: 255, b: 0))
    }
}

import CoreGraphics
import Foundation

// Port of parseItermColors in src/main/themes.js. v2 read the plist with regular expressions and
// treated every colour as sRGB; here PropertyListSerialization does the reading and the declared
// "Color Space" is kept, because iTerm2 writes P3 values that look wrong if taken as sRGB.

public enum DeclaredSpace: Sendable {
    case sRGB
    case displayP3
}

/// A colour as written in the file: components 0...1 in the declared space.
public struct DeclaredColor: Sendable, Equatable {
    public var space: DeclaredSpace
    public var r: Double
    public var g: Double
    public var b: Double

    public init(space: DeclaredSpace, r: Double, g: Double, b: Double) {
        self.space = space
        self.r = r
        self.g = g
        self.b = b
    }

    /// sRGB colour used to derive the palette. sRGB values quantize exactly like v2's hex
    /// conversion; P3 values are converted by CoreGraphics and then clamped to the sRGB gamut.
    public var sRGBForDerivation: RGB {
        switch space {
        case .sRGB:
            return RGB(unit: r, g, b)
        case .displayP3:
            guard let p3 = CGColorSpace(name: CGColorSpace.displayP3),
                  let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let source = CGColor(colorSpace: p3, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1]),
                  let converted = source.converted(to: srgb, intent: .defaultIntent, options: nil),
                  let c = converted.components, c.count >= 3
            else {
                assertionFailure("Display P3 to sRGB conversion failed")
                return RGB(unit: r, g, b)
            }
            return RGB(unit: Double(c[0]), Double(c[1]), Double(c[2]))
        }
    }
}

public struct ParsedScheme: Sendable, Equatable {
    public var background: DeclaredColor
    public var foreground: DeclaredColor
    public var selection: DeclaredColor?
    public var selectedText: DeclaredColor?
    public var cursor: DeclaredColor?

    public init(
        background: DeclaredColor, foreground: DeclaredColor,
        selection: DeclaredColor? = nil, selectedText: DeclaredColor? = nil, cursor: DeclaredColor? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.selection = selection
        self.selectedText = selectedText
        self.cursor = cursor
    }

    var schemeColors: SchemeColors {
        SchemeColors(
            background: background.sRGBForDerivation,
            foreground: foreground.sRGBForDerivation,
            selection: selection?.sRGBForDerivation,
            selectedText: selectedText?.sRGBForDerivation,
            cursor: cursor?.sRGBForDerivation)
    }
}

private func declaredColor(_ value: Any?) -> DeclaredColor? {
    guard let dict = value as? [String: Any] else { return nil }

    func channel(_ name: String) -> Double? {
        guard let n = dict["\(name) Component"] as? NSNumber else { return nil }
        let v = n.doubleValue
        return v.isFinite ? v : nil
    }
    guard let r = channel("Red"), let g = channel("Green"), let b = channel("Blue") else { return nil }

    // iTerm2 writes "sRGB", "P3" or "Calibrated"; an absent key and anything unrecognised stay
    // sRGB, which is what v2 assumed for every file.
    let space: DeclaredSpace = (dict["Color Space"] as? String) == "P3" ? .displayP3 : .sRGB
    return DeclaredColor(space: space, r: r, g: g, b: b)
}

/// Background and foreground are required; the optional colours are nil when absent or unreadable.
public func parseItermColors(_ data: Data) -> ParsedScheme? {
    guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [String: Any],
          let background = declaredColor(root["Background Color"]),
          let foreground = declaredColor(root["Foreground Color"])
    else { return nil }

    return ParsedScheme(
        background: background,
        foreground: foreground,
        selection: declaredColor(root["Selection Color"]),
        selectedText: declaredColor(root["Selected Text Color"]),
        cursor: declaredColor(root["Cursor Color"]))
}

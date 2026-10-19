import Foundation

// Port of src/main/palette.js. Every helper that returns a hex string in JS returns an RGB here,
// so values are quantized to 8 bits at exactly the same points and the output strings match v2.

public struct RGB: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Accepts `#rgb`, `#rrggbb`, with or without the leading `#`.
    public init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.flatMap { [$0, $0] }.map(String.init).joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(r: UInt8((v >> 16) & 0xff), g: UInt8((v >> 8) & 0xff), b: UInt8(v & 0xff))
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Channels as 0...1 doubles, like JS `hexToRgb`.
    fileprivate var unit: (r: Double, g: Double, b: Double) {
        (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }

    init(unit r: Double, _ g: Double, _ b: Double) {
        func q(_ c: Double) -> UInt8 {
            UInt8((min(1, max(0, c)) * 255).rounded(.toNearestOrAwayFromZero))
        }
        self.init(r: q(r), g: q(g), b: q(b))
    }
}

public struct RGBA: Equatable, Sendable {
    public var rgb: RGB
    public var alpha: Double

    public init(rgb: RGB, alpha: Double) {
        self.rgb = rgb
        self.alpha = alpha
    }

    /// `rgba(r, g, b, A)` with A rounded to 3 places and printed the way JS prints numbers.
    public var css: String {
        let rounded = (alpha * 1000).rounded(.toNearestOrAwayFromZero) / 1000
        let a = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return "rgba(\(rgb.r), \(rgb.g), \(rgb.b), \(a))"
    }
}

public struct SchemeColors: Sendable {
    public var background: RGB
    public var foreground: RGB
    public var selection: RGB?
    public var selectedText: RGB?
    public var cursor: RGB?

    public init(background: RGB, foreground: RGB, selection: RGB? = nil, selectedText: RGB? = nil, cursor: RGB? = nil) {
        self.background = background
        self.foreground = foreground
        self.selection = selection
        self.selectedText = selectedText
        self.cursor = cursor
    }
}

public struct Palette: Sendable {
    public var isDark: Bool
    public var background: RGB
    public var text: RGB
    /// `--bg-translucent`
    public var surface: RGBA
    /// `--bg-1-translucent`
    public var activeLine: RGBA
    public var selection: RGB
    public var selectedText: RGB
    public var cursor: RGB
    /// `--overlay-bg`
    public var overlayBackground: RGBA
    /// `--overlay-text`
    public var overlayText: RGBA
    /// `--overlay-text-hover`
    public var overlayTextHover: RGBA
}

/// Built-in schemes: the dark one is the original palette, the light one its Solarized counterpart.
public struct BuiltInScheme: Sendable {
    public let id: String
    public let name: String
    public let colors: SchemeColors

    public static let dark = BuiltInScheme(
        id: "built-in:dark", name: "Dark",
        colors: SchemeColors(background: RGB(hex: "#002b36")!, foreground: RGB(hex: "#829696")!))
    public static let light = BuiltInScheme(
        id: "built-in:light", name: "Light",
        colors: SchemeColors(background: RGB(hex: "#fdf6e3")!, foreground: RGB(hex: "#657b83")!))
}

// MARK: - Colour maths (palette.js:15-90)

private func rgbToHsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
    let (r, g, b) = c.unit
    let mx = max(r, g, b)
    let mn = min(r, g, b)
    let l = (mx + mn) / 2
    if mx == mn { return (0, 0, l) }

    let d = mx - mn
    let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    let h: Double
    if mx == r {
        h = ((g - b) / d + (g < b ? 6 : 0)) / 6
    } else if mx == g {
        h = ((b - r) / d + 2) / 6
    } else {
        h = ((r - g) / d + 4) / 6
    }
    return (h, s, l)
}

private func hslToRgb(h: Double, s: Double, l: Double) -> RGB {
    if s == 0 { return RGB(unit: l, l, l) }

    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func channel(_ t: Double) -> Double {
        // JS `%` keeps the dividend's sign, and so does truncatingRemainder.
        let u = (t + 1).truncatingRemainder(dividingBy: 1)
        if u < 1.0 / 6 { return p + (q - p) * 6 * u }
        if u < 1.0 / 2 { return q }
        if u < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - u) * 6 }
        return p
    }
    return RGB(unit: channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
}

private func clamp01(_ n: Double) -> Double { min(1, max(0, n)) }

/// Sass's lighten()/darken(), plus optional desaturation, in one HSL round-trip.
private func adjust(_ c: RGB, lightness: Double = 0, saturation: Double = 1) -> RGB {
    let (h, s, l) = rgbToHsl(c)
    return hslToRgb(h: h, s: clamp01(s * saturation), l: clamp01(l + lightness / 100))
}

private func shift(_ c: RGB, _ delta: Double) -> RGB { adjust(c, lightness: delta) }

/// Blend two colours, `t` of the way from `a` to `b`.
private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    let x = a.unit
    let y = b.unit
    return RGB(unit: x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t)
}

private func withAlpha(_ c: RGB, _ alpha: Double) -> RGBA { RGBA(rgb: c, alpha: alpha) }

/// WCAG relative luminance.
func luminance(_ c: RGB) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let (r, g, b) = c.unit
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

// 0.179 is the luminance at which white and black text contrast equally.
public func isDark(_ background: RGB) -> Bool { luminance(background) < 0.179 }

// MARK: - Derivation (palette.js:96-188)

public func derivePalette(_ colors: SchemeColors) -> Palette {
    let background = colors.background
    let foreground = colors.foreground
    let dark = isDark(background)

    // Toward the background: darker text on dark schemes, lighter on light ones.
    func recede(_ pct: Double) -> RGB { shift(foreground, dark ? -pct : pct) }
    func ink(_ alpha: Double) -> RGBA {
        withAlpha(dark ? RGB(r: 255, g: 255, b: 255) : RGB(r: 0, g: 0, b: 0), alpha)
    }

    // The editor surface is close to opaque so schemes stay distinguishable over vibrancy.
    let surfaceAlpha = 0.85
    // Mix toward the foreground so overlays keep contrast on any scheme.
    func overlay(_ t: Double) -> RGB { mix(background, foreground, t) }
    // Active line stays half-transparent so a selection still reads underneath it.
    let activeLineMix = 0.26
    let activeLineAlpha = 0.5

    return Palette(
        isDark: dark,
        background: background,
        text: foreground,
        surface: withAlpha(background, surfaceAlpha),
        activeLine: withAlpha(overlay(activeLineMix), activeLineAlpha),
        selection: colors.selection ?? overlay(0.38),
        selectedText: colors.selectedText ?? foreground,
        cursor: colors.cursor ?? recede(5),
        overlayBackground: ink(0.1),
        overlayText: ink(0.4),
        overlayTextHover: ink(0.7))
}

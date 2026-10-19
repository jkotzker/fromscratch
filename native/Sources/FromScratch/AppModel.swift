import AppKit
import FromScratchCore

/// The app's state: the two stores, the known schemes and the one in use. Views register a closure
/// in `didChange` and re-read what they need when it runs.
@MainActor
final class AppModel {
    let dataDirectory: URL
    let settings: SettingsStore
    let content: ContentStore
    var schemes: SchemeLibrary
    private(set) var scheme: Scheme
    var didChange: [@MainActor () -> Void] = []

    init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        settings = SettingsStore(directory: dataDirectory)
        content = ContentStore(directory: dataDirectory)
        schemes = SchemeLibrary(
            themesDirectory: dataDirectory.appendingPathComponent(SchemeLibrary.themesDirname, isDirectory: true))
        // Resolving is pure: a stored id whose theme file is gone shows the first built-in without
        // overwriting the setting, as resolveScheme does in src/main/index.js.
        scheme = schemes.resolve(id: settings.colorSchemeId)
        Self.applyAppearance(for: scheme)
    }

    /// Makes `scheme` the one on screen. Persisting a choice is the caller's job (the scheme menu,
    /// Task 10); launch applies the resolved scheme without writing it back.
    func apply(scheme: Scheme) {
        self.scheme = scheme
        Self.applyAppearance(for: scheme)
        notify()
    }

    func notify() {
        for observer in didChange { observer() }
    }

    // v2 set nativeTheme.themeSource from the scheme (applyScheme in src/main/index.js): the
    // vibrancy material follows the appearance, so a light scheme needs a light backdrop.
    private static func applyAppearance(for scheme: Scheme) {
        NSApp.appearance = NSAppearance(named: scheme.isDark ? .darkAqua : .aqua)
    }
}

extension NSColor {
    /// A colour from a scheme file, drawn in the space it was declared in so P3 themes keep their gamut.
    convenience init(declared c: DeclaredColor, alpha: CGFloat = 1) {
        switch c.space {
        case .displayP3:
            self.init(displayP3Red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
        case .sRGB:
            self.init(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
        }
    }

    /// A colour derived by the palette maths, which works in sRGB.
    convenience init(srgb c: RGB, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
    }

    convenience init(srgb c: RGBA) {
        self.init(srgb: c.rgb, alpha: CGFloat(c.alpha))
    }
}

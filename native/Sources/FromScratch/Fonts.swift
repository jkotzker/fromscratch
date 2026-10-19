import AppKit
import CoreText
import FromScratchCore

/// The editor font. v2 bundled Fira Code and used its heavier Retina cut on macOS
/// (`body[data-platform='darwin']` in app.css); a chosen family that is no longer installed falls
/// back to it, as the CSS `var(--font-family, 'FiraCode-Retina')` fallback did.
@MainActor
enum Fonts {
    /// PostScript name of `Resources/FiraCode-Retina.otf` (read with `fc-scan`).
    static let bundledPostScriptName = "FiraCode-Retina"

    private static var didRegister = false

    /// Registers the bundled face for this process only, so it never appears in other apps.
    static func registerBundled() {
        guard !didRegister else { return }
        didRegister = true
        // SPM resources are not used for the app target: the build script copies the font into
        // Contents/Resources. `swift run` has no bundle, so the system monospaced font stands in.
        guard let url = Bundle.main.url(forResource: bundledPostScriptName, withExtension: "otf") else {
            NSLog("\(bundledPostScriptName).otf is not in the app bundle; using the system monospaced font")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            NSLog("Could not register \(url.lastPathComponent): \(reason)")
        }
    }

    /// The font for a setting. A family that cannot be found falls back to the bundled face at the
    /// same size; the setting itself is left alone so the font returns if it is reinstalled.
    static func font(for setting: FontSetting) -> NSFont {
        let size = CGFloat(setting.size)
        if let family = setting.family {
            if let face = setting.face, let font = NSFont(name: face, size: size), font.familyName == family {
                return font
            }
            // Weight 5 is the regular weight in NSFontManager's 0-15 scale.
            if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
                return font
            }
        }
        return bundled(size: size)
    }

    static func bundled(size: CGFloat) -> NSFont {
        NSFont(name: bundledPostScriptName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

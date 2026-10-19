import AppKit
import FromScratchCore

/// The editor font setting. It is `NSFontManager.shared.target`, so the font panel's choices
/// arrive here wherever focus is (the editor or the Settings window) and are always stored, rather
/// than changing only the text view's font for this run.
@MainActor
final class FontController: NSObject, NSFontChanging {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// The font the editor draws with, which is the fallback face when the stored family is gone.
    var currentFont: NSFont {
        Fonts.font(for: model.settings.font)
    }

    /// "<Family> <size> pt", for the Settings window. The family of the font actually in use.
    var displayDescription: String {
        let font = currentFont
        return "\(font.familyName ?? font.fontName) \(model.settings.font.size) pt"
    }

    // MARK: Font panel

    func changeFont(_ sender: NSFontManager?) {
        store((sender ?? .shared).convert(currentFont))
    }

    /// Family, face and size only: the panel's colour, underline and shadow controls would style
    /// text that is plain and cannot keep them.
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }

    /// Opens the font panel showing the current font (Settings › Choose…).
    func showFontPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(currentFont, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    /// Stores `font` as the setting: no family for the bundled face, the family otherwise, the
    /// PostScript name only when the face is not the family's regular one, and a rounded and
    /// clamped size. Fonts.font(for:) turns the stored values back into this font.
    func store(_ font: NSFont) {
        let size = FontSetting.clamp(Double(font.pointSize))
        var setting = FontSetting(family: nil, size: size)
        if font.fontName != Fonts.bundled(size: font.pointSize).fontName {
            let family = font.familyName ?? font.fontName
            // Weight 5 is the regular weight in NSFontManager's 0-15 scale, as in Fonts.font(for:).
            let regular = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: font.pointSize)
            setting = FontSetting(family: family, size: size,
                                  face: regular?.fontName == font.fontName ? nil : font.fontName)
        }
        model.setFont(setting)
        // Keeps the panel on what is now stored, which differs from the choice when it was clamped.
        NSFontManager.shared.setSelectedFont(currentFont, isMultiple: false)
    }

    // MARK: Size commands (⌘+, ⌘−, ⌘0)

    func increaseFontSize() { setSize(model.settings.font.size + 1) }
    func decreaseFontSize() { setSize(model.settings.font.size - 1) }
    func resetFontSize() { setSize(FontSetting.defaultSize) }

    private func setSize(_ size: Int) {
        var setting = model.settings.font
        setting.size = FontSetting.clamp(Double(size))
        model.setFont(setting)
        NSFontManager.shared.setSelectedFont(currentFont, isMultiple: false)
    }
}

import AppKit
import CoreText
import FromScratchCore
import Testing
@testable import FromScratch

// MARK: Fixtures

/// An `.itermcolors` file with the given background and foreground (0...1 components), optional
/// selection colours, and a declared colour space.
private func theme(background: (Double, Double, Double), foreground: (Double, Double, Double),
                   selection: (Double, Double, Double)? = nil, selectedText: (Double, Double, Double)? = nil,
                   space: String = "sRGB") -> String {
    func color(_ key: String, _ c: (Double, Double, Double)) -> String {
        """
        <key>\(key)</key><dict>
        <key>Color Space</key><string>\(space)</string>
        <key>Red Component</key><real>\(c.0)</real><key>Green Component</key><real>\(c.1)</real>
        <key>Blue Component</key><real>\(c.2)</real>
        </dict>
        """
    }
    var body = color("Background Color", background) + color("Foreground Color", foreground)
    if let selection { body += color("Selection Color", selection) }
    if let selectedText { body += color("Selected Text Color", selectedText) }
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>\(body)</dict></plist>
        """
}

private let darkTheme = theme(background: (0.1, 0.1, 0.15), foreground: (0.8, 0.8, 0.8),
                              selection: (0.2, 0.3, 0.6), selectedText: (1, 1, 1))
private let lightTheme = theme(background: (0.98, 0.97, 0.95), foreground: (0.2, 0.2, 0.2))
private let p3Theme = theme(background: (0.05, 0.05, 0.1), foreground: (0.9, 0.9, 0.8),
                            selection: (0.8, 0.4, 0.2), selectedText: (0, 0, 0), space: "P3")

/// A temporary data folder holding `themes` (file name without extension → contents) and,
/// optionally, a settings.json.
@MainActor
private func dataFolder(themes: [String: String] = [:], settings: String? = nil) throws -> URL {
    // AppModel sets NSApp.appearance, which needs the shared application.
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FromScratchTests-\(UUID().uuidString)", isDirectory: true)
    let themesDirectory = directory.appendingPathComponent(SchemeLibrary.themesDirname, isDirectory: true)
    try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
    for (name, contents) in themes {
        try contents.write(to: themesDirectory.appendingPathComponent("\(name).itermcolors"),
                           atomically: true, encoding: .utf8)
    }
    if let settings {
        try settings.write(to: directory.appendingPathComponent(SettingsStore.fileName), atomically: true, encoding: .utf8)
    }
    return directory
}

@MainActor
private func storedSettings(in directory: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: directory.appendingPathComponent(SettingsStore.fileName))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The bundled face, registered from the package's Resources folder (tests have no app bundle).
@MainActor
private func registerBundledFont() {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/FiraCode-Retina.otf")
    if NSFont(name: Fonts.bundledPostScriptName, size: 12) == nil {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// A pixel of `view` as rendered offscreen, with the colour of a reference view filled with
/// `reference` read the same way, so both go through the same colour conversion.
@MainActor
private func pixel(of view: NSView, at point: NSPoint) -> NSColor? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / view.bounds.width
    // Bitmap rows run top to bottom, as the flipped text view does.
    let y = view.isFlipped ? point.y : view.bounds.height - point.y
    return rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))
}

/// `color` filled into a small view in `window`, read back like `pixel(of:at:)`. In the same window
/// so it is drawn into the same colour space as the view it is compared with.
@MainActor
private func rendered(_ color: NSColor, in window: NSWindow?) -> NSColor? {
    final class Swatch: NSView {
        var color: NSColor = .clear
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            bounds.fill(using: .sourceOver)
        }
    }
    let swatch = Swatch(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
    swatch.color = color
    window?.contentView?.addSubview(swatch)
    defer { swatch.removeFromSuperview() }
    return pixel(of: swatch, at: NSPoint(x: 2, y: 2))
}

private func components(_ color: NSColor?) -> [CGFloat] {
    guard let color else { return [] }
    return (0..<color.numberOfComponents).map { i in
        var c = [CGFloat](repeating: 0, count: color.numberOfComponents)
        color.getComponents(&c)
        return c[i]
    }
}

private func close(_ a: [CGFloat], _ b: [CGFloat], tolerance: CGFloat = 0.02) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

// MARK: Schemes

@MainActor
@Suite(.serialized)
struct SchemeControllerTests {
    init() { silenceFeedback() }

    @Test func selectStoresTheIdAndAppliesIt() throws {
        let directory = try dataFolder()
        let model = AppModel(dataDirectory: directory)
        let schemes = SchemeController(model: model)

        schemes.select(id: BuiltInScheme.light.id)
        #expect(model.scheme.id == BuiltInScheme.light.id)
        #expect(model.settings.colorSchemeId == BuiltInScheme.light.id)
        #expect(NSApp.appearance?.name == .aqua)

        schemes.select(id: BuiltInScheme.dark.id)
        #expect(NSApp.appearance?.name == .darkAqua)
        model.settings.flush()
        #expect(try storedSettings(in: directory)["colorScheme"] as? String == BuiltInScheme.dark.id)
    }

    /// As selectScheme in src/main/index.js: an id that does not resolve stores the resolved one.
    @Test func selectingAnUnknownIdStoresTheFallback() throws {
        let model = AppModel(dataDirectory: try dataFolder())
        SchemeController(model: model).select(id: "file:Nope")
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        #expect(model.settings.colorSchemeId == BuiltInScheme.dark.id)
    }

    @Test func aMissingStoredIdRendersDarkWithoutRewritingIt() throws {
        let directory = try dataFolder(settings: #"{"version":1,"colorScheme":"file:Gone"}"#)
        let model = AppModel(dataDirectory: directory)
        _ = SchemeController(model: model)
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        #expect(NSApp.appearance?.name == .darkAqua)
        model.settings.flush()
        #expect(try storedSettings(in: directory)["colorScheme"] as? String == "file:Gone")
    }

    /// toggleScheme in App.jsx: the first scheme whose darkness differs from the current one.
    @Test func toggleLightDarkPicksTheFirstSchemeOfTheOtherKind() throws {
        let model = AppModel(dataDirectory: try dataFolder(themes: ["Night": darkTheme, "Paper": lightTheme]))
        let schemes = SchemeController(model: model)
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        schemes.toggleLightDark()
        #expect(model.scheme.id == BuiltInScheme.light.id)
        schemes.toggleLightDark()
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        schemes.select(id: "file:Night")
        schemes.toggleLightDark()
        #expect(model.scheme.id == BuiltInScheme.light.id)
        schemes.select(id: "file:Paper")
        schemes.toggleLightDark()
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        #expect(model.settings.colorSchemeId == BuiltInScheme.dark.id)
    }

    @Test func reloadRescansAndReappliesTheStoredScheme() throws {
        let directory = try dataFolder(themes: ["Mine": darkTheme])
        let model = AppModel(dataDirectory: directory)
        let schemes = SchemeController(model: model)
        schemes.select(id: "file:Mine")
        #expect(model.scheme.isDark)

        let file = directory.appendingPathComponent("themes/Mine.itermcolors")
        try lightTheme.write(to: file, atomically: true, encoding: .utf8)
        try darkTheme.write(to: directory.appendingPathComponent("themes/Added.itermcolors"), atomically: true, encoding: .utf8)
        var notified = 0
        model.didChange.append { notified += 1 }
        schemes.reload()
        #expect(model.scheme.id == "file:Mine")
        #expect(!model.scheme.isDark)
        #expect(model.schemes.all.map(\.id).contains("file:Added"))
        #expect(notified > 0)

        // A file deleted since it was chosen falls back to Dark and leaves the setting alone.
        try FileManager.default.removeItem(at: file)
        schemes.reload()
        #expect(model.scheme.id == BuiltInScheme.dark.id)
        #expect(model.settings.colorSchemeId == "file:Mine")
    }

    @Test func openThemesFolderCreatesItFirst() throws {
        let directory = try dataFolder()
        let themes = directory.appendingPathComponent(SchemeLibrary.themesDirname, isDirectory: true)
        let schemes = SchemeController(model: AppModel(dataDirectory: directory))
        try FileManager.default.removeItem(at: themes)
        var opened: [URL] = []
        schemes.openURL = { opened.append($0) }
        schemes.openThemesFolder()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: themes.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(opened.map(\.standardizedFileURL) == [themes.standardizedFileURL])
    }

    /// Built-ins first, then files; one radio checkmark on the scheme in use; the two commands last.
    @Test func colourSchemeMenuListsSchemesWithTheActiveOneChecked() throws {
        let model = AppModel(dataDirectory: try dataFolder(themes: ["Night": darkTheme]))
        let schemes = SchemeController(model: model)
        let main = MainMenu.build(from: Commands.defaults, schemeMenuDelegate: schemes)
        let view = try #require(main.item(withTitle: "View")?.submenu)
        let holder = try #require(view.item(withTitle: "Colour Scheme"))
        let menu = try #require(holder.submenu)
        #expect(menu.delegate === schemes)

        schemes.select(id: "file:Night")
        schemes.menuNeedsUpdate(menu)
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Dark", "Light", "Night", "-", "Reload Schemes", "Open Themes Folder"])
        #expect(menu.items.filter { $0.state == .on }.map(\.title) == ["Night"])
        // Rebuilding must not duplicate the scheme items.
        schemes.menuNeedsUpdate(menu)
        #expect(menu.items.count == titles.count)

        let light = try #require(menu.item(withTitle: "Light"))
        #expect(NSApp.sendAction(try #require(light.action), to: light.target, from: light))
        #expect(model.scheme.id == BuiltInScheme.light.id)
        schemes.menuNeedsUpdate(menu)
        #expect(menu.items.filter { $0.state == .on }.map(\.title) == ["Light"])
    }

    /// Declared colours keep their space; derived ones are sRGB.
    @Test func editorUsesDeclaredSpacesAndSelectionAttributes() throws {
        let model = AppModel(dataDirectory: try dataFolder(themes: ["Wide": p3Theme, "Plain": darkTheme]))
        let schemes = SchemeController(model: model)
        let editor = EditorWindowController(model: model)
        let textView = editor.textView

        schemes.select(id: "file:Wide")
        var background = try #require(textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        var foreground = try #require(textView.selectedTextAttributes[.foregroundColor] as? NSColor)
        #expect(background.colorSpace == .displayP3)
        #expect(close(components(background), [0.8, 0.4, 0.2, 1]))
        #expect(close(components(foreground), [0, 0, 0, 1]))
        #expect(textView.textColor?.colorSpace == .displayP3)

        schemes.select(id: "file:Plain")
        background = try #require(textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        foreground = try #require(textView.selectedTextAttributes[.foregroundColor] as? NSColor)
        #expect(background.colorSpace == .sRGB)
        #expect(close(components(background), [0.2, 0.3, 0.6, 1]))
        #expect(close(components(foreground), [1, 1, 1, 1]))

        // The built-in has no selection colours: the derived selection, and the text colour.
        schemes.select(id: BuiltInScheme.dark.id)
        let palette = model.scheme.palette
        background = try #require(textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        foreground = try #require(textView.selectedTextAttributes[.foregroundColor] as? NSColor)
        #expect(background == NSColor(srgb: palette.selection))
        #expect(close(components(foreground), components(NSColor(srgb: palette.text))))
        #expect(textView.activeLineColor == NSColor(srgb: palette.activeLine))
    }
}

// MARK: Current-line band

@MainActor
@Suite(.serialized)
struct CurrentLineBandTests {
    init() { silenceFeedback() }

    private func makeEditor(_ text: String, highlight: Bool = true) throws -> (EditorWindowController, AppModel) {
        let model = AppModel(dataDirectory: try dataFolder())
        model.settings.highlightCurrentLine = highlight
        let editor = EditorWindowController(model: model)
        editor.textView.string = text
        editor.window?.makeFirstResponder(editor.textView)
        editor.textView.layoutSubtreeIfNeeded()
        return (editor, model)
    }

    private func caret(_ location: Int, in view: NSTextView) {
        view.setSelectedRange(NSRange(location: location, length: 0))
    }

    @Test func bandCoversEveryVisualLineOfTheCaretsParagraph() throws {
        let long = String(repeating: "word ", count: 80)
        let (editor, _) = try makeEditor("first\n\(long)\nlast")
        let view = editor.textView
        let lineHeight = 1.25 * (view.font?.pointSize ?? 16)
        caret(10, in: view)
        let rects = view.currentLineBandRects()
        #expect(rects.count == 1)
        let band = try #require(rects.first)
        #expect(band.height >= 3 * lineHeight - 0.5)
        #expect(abs(band.minY - (view.textContainerOrigin.y + lineHeight)) < 0.5)
        // The `.cm-line` box: from the text's leading edge to the right edge of the editor.
        #expect(abs(band.minX - view.textContainerInset.width) < 0.5)
        #expect(abs(band.maxX - view.bounds.width) < 0.5)

        caret(0, in: view)
        let first = try #require(view.currentLineBandRects().first)
        #expect(abs(first.height - lineHeight) < 0.5)
        #expect(abs(first.minY - view.textContainerOrigin.y) < 0.5)
    }

    @Test func bandFollowsTheCaretOntoAnEmptyLastLine() throws {
        let (editor, _) = try makeEditor("one\ntwo\n")
        let view = editor.textView
        let lineHeight = 1.25 * (view.font?.pointSize ?? 16)
        caret(8, in: view)
        let band = try #require(view.currentLineBandRects().first)
        #expect(abs(band.minY - (view.textContainerOrigin.y + 2 * lineHeight)) < 0.5)
        #expect(abs(band.height - lineHeight) < 0.5)

        let (empty, _) = try makeEditor("")
        caret(0, in: empty.textView)
        #expect(empty.textView.currentLineBandRects().count == 1)
    }

    @Test func noBandWithASelectionOrWhenSwitchedOff() throws {
        let (editor, model) = try makeEditor("one\ntwo")
        let view = editor.textView
        view.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(view.currentLineBandRects().isEmpty)
        // Every range must be empty, not just the first.
        view.selectedRanges = [NSValue(range: NSRange(location: 1, length: 0)), NSValue(range: NSRange(location: 5, length: 1))]
        #expect(view.currentLineBandRects().isEmpty)
        // NSTextView keeps a single insertion point (measured: two empty ranges collapse to the
        // first), so there is one band per caret it actually holds.
        view.selectedRanges = [NSValue(range: NSRange(location: 1, length: 0)), NSValue(range: NSRange(location: 5, length: 0))]
        #expect(view.currentLineBandRects().count == view.selectedRanges.count)

        caret(1, in: view)
        model.setHighlightCurrentLine(false)
        #expect(!view.highlightsCurrentLine)
        #expect(view.currentLineBandRects().isEmpty)
        model.setHighlightCurrentLine(true)
        #expect(view.currentLineBandRects().count == 1)
    }

    /// Rendered: the band is the active-line colour between its fades and nothing under a selection.
    @Test func bandIsDrawnAsAGradientBehindTheText() throws {
        // A line of spaces: no glyph covers the sampled pixels.
        let (editor, model) = try makeEditor(String(repeating: " ", count: 10))
        let view = editor.textView
        caret(0, in: view)
        let band = try #require(view.currentLineBandRects().first)
        let em = view.font?.pointSize ?? 16
        let middle = NSPoint(x: band.midX, y: band.midY)
        let expected = rendered(NSColor(srgb: model.scheme.palette.activeLine), in: view.window)
        #expect(close(components(pixel(of: view, at: middle)), components(expected)))
        // Transparent at the left edge, fading in over the first em.
        let edge = components(pixel(of: view, at: NSPoint(x: band.minX + 0.5, y: band.midY)))
        #expect((edge.last ?? 1) < 0.1)
        let ramp = components(pixel(of: view, at: NSPoint(x: band.minX + em / 2, y: band.midY)))
        #expect((ramp.last ?? 0) > 0.1 && (ramp.last ?? 1) < (components(expected).last ?? 0) - 0.05)

        view.setSelectedRange(NSRange(location: 0, length: 3))
        let afterSelecting = components(pixel(of: view, at: NSPoint(x: band.maxX - 3 * em, y: band.midY)))
        #expect((afterSelecting.last ?? 1) < 0.01)
    }
}

// MARK: Font

@MainActor
@Suite(.serialized)
struct FontControllerTests {
    init() { silenceFeedback() }

    private func make() throws -> (FontController, AppModel, URL) {
        registerBundledFont()
        let directory = try dataFolder()
        let model = AppModel(dataDirectory: directory)
        return (FontController(model: model), model, directory)
    }

    @Test func storesFamilyFaceAndClampedSize() throws {
        let (fonts, model, directory) = try make()

        fonts.store(try #require(NSFont(name: Fonts.bundledPostScriptName, size: 18.4)))
        #expect(model.settings.font == FontSetting(family: nil, size: 18, face: nil))

        fonts.store(try #require(NSFont(name: "Menlo-Regular", size: 13)))
        #expect(model.settings.font == FontSetting(family: "Menlo", size: 13, face: nil))

        fonts.store(try #require(NSFont(name: "Menlo-Bold", size: 100)))
        #expect(model.settings.font == FontSetting(family: "Menlo", size: 72, face: "Menlo-Bold"))
        model.settings.flush()
        let stored = try storedSettings(in: directory)
        #expect(stored["fontFace"] as? String == "Menlo-Bold")
        #expect((stored["font"] as? [String: Any])?["family"] as? String == "Menlo")
        #expect((stored["font"] as? [String: Any])?["size"] as? Double == 72)

        fonts.store(try #require(NSFont(name: "Menlo-Regular", size: 3)))
        #expect(model.settings.font == FontSetting(family: "Menlo", size: 8, face: nil))
        #expect(stored.keys.contains("fontFace"))
        model.settings.flush()
        #expect(try storedSettings(in: directory)["fontFace"] == nil)
    }

    /// The font panel's path: the font manager sends changeFont: to its target, which converts the
    /// current font. Size Up and Bold stand in for choices made in the panel.
    @Test func changeFontFromTheFontManagerIsStored() throws {
        let (fonts, model, _) = try make()
        model.settings.font = FontSetting(family: "Menlo", size: 16)
        let manager = NSFontManager.shared
        // The font manager does not clear its target when the target is freed (measured: reading
        // it afterwards crashed in objc_retain), so it is cleared before `fonts` goes away.
        defer { manager.target = nil }
        manager.target = fonts

        let bold = NSMenuItem()
        bold.tag = Int(NSFontTraitMask.boldFontMask.rawValue)
        manager.addFontTrait(bold)
        #expect(model.settings.font.family == "Menlo")
        #expect(model.settings.font.face == "Menlo-Bold")

        let sizeUp = NSMenuItem()
        sizeUp.tag = Int(NSFontAction.sizeUpFontAction.rawValue)
        manager.modifyFont(sizeUp)
        #expect(model.settings.font.size > 16)
        #expect(model.settings.font.face == "Menlo-Bold")
    }

    @Test func sizeCommandsStepByOneAndReset() throws {
        let (fonts, model, _) = try make()
        var changes = 0
        model.didChange.append { changes += 1 }
        fonts.increaseFontSize()
        #expect(model.settings.font.size == 17)
        fonts.decreaseFontSize()
        fonts.decreaseFontSize()
        #expect(model.settings.font.size == 15)
        fonts.resetFontSize()
        #expect(model.settings.font.size == 16)
        #expect(changes == 4)
        model.settings.font = FontSetting(size: 72)
        fonts.increaseFontSize()
        #expect(model.settings.font.size == 72)
        model.settings.font = FontSetting(size: 8)
        fonts.decreaseFontSize()
        #expect(model.settings.font.size == 8)
    }

    /// The editor follows: font, the fixed 1.25 line height, and the band's em.
    @Test func editorTakesTheNewFont() throws {
        let (fonts, model, _) = try make()
        let editor = EditorWindowController(model: model)
        fonts.store(try #require(NSFont(name: "Menlo-Bold", size: 20)))
        #expect(editor.textView.font?.fontName == "Menlo-Bold")
        #expect(editor.textView.defaultParagraphStyle?.minimumLineHeight == 25)
        #expect(editor.textView.defaultParagraphStyle?.maximumLineHeight == 25)
    }

    @Test func descriptionShowsFamilyAndSize() throws {
        let (fonts, model, _) = try make()
        model.settings.font = FontSetting(family: "Menlo", size: 13, face: "Menlo-Bold")
        #expect(fonts.displayDescription == "Menlo 13 pt")
        model.settings.font = FontSetting(family: "No Such Family Anywhere", size: 14)
        // A family that is gone shows what is drawn: the bundled face.
        #expect(fonts.displayDescription == "\(Fonts.bundled(size: 14).familyName ?? "") 14 pt")
        // …without rewriting the setting, so the font comes back if the family is reinstalled.
        #expect(fonts.currentFont.fontName == Fonts.bundled(size: 14).fontName)
        #expect(model.settings.font.family == "No Such Family Anywhere")
    }
}

// MARK: Settings window and menu sync

@MainActor
@Suite(.serialized)
struct SettingsSyncTests {
    init() { silenceFeedback() }

    /// attach(model:) makes the font controller the font manager's target, which the manager does
    /// not clear when it is freed; keeping the delegates alive keeps that target valid for the
    /// rest of the test run, as the app delegate is for the app's.
    private static var delegates: [AppDelegate] = []

    private func make(themes: [String: String] = [:]) throws -> (AppDelegate, AppModel) {
        registerBundledFont()
        let model = AppModel(dataDirectory: try dataFolder(themes: themes))
        let delegate = AppDelegate()
        delegate.attach(model: model)
        Self.delegates.append(delegate)
        return (delegate, model)
    }

    @Test func windowIsATitledNonResizableSettingsWindow() throws {
        let (delegate, _) = try make()
        let window = try #require(delegate.settingsWindow?.window)
        #expect(window.title == "Settings")
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.closable))
    }

    @Test func highlightStaysInSyncBetweenMenuAndSettings() throws {
        let (delegate, model) = try make()
        let settings = try #require(delegate.settingsWindow?.viewModel)
        let item = NSMenuItem(title: "Highlight Current Line",
                              action: #selector(AppDelegate.toggleHighlightCurrentLine(_:)), keyEquivalent: "")
        #expect(delegate.validateMenuItem(item))
        #expect(item.state == .on)
        #expect(settings.highlightCurrentLine)

        // Menu → Settings
        delegate.toggleHighlightCurrentLine(item)
        #expect(!model.settings.highlightCurrentLine)
        #expect(!settings.highlightCurrentLine)
        _ = delegate.validateMenuItem(item)
        #expect(item.state == .off)

        // Settings → menu
        settings.highlightCurrentLine = true
        #expect(model.settings.highlightCurrentLine)
        _ = delegate.validateMenuItem(item)
        #expect(item.state == .on)
    }

    @Test func schemeAndFontStayInSyncBetweenMenuAndSettings() throws {
        let (delegate, model) = try make(themes: ["Night": darkTheme])
        let settings = try #require(delegate.settingsWindow?.viewModel)
        #expect(settings.schemes.map(\.name) == ["Dark", "Light", "Night"])
        #expect(settings.selectedSchemeId == BuiltInScheme.dark.id)

        delegate.toggleLightDark(nil)
        #expect(settings.selectedSchemeId == BuiltInScheme.light.id)

        settings.selectedSchemeId = "file:Night"
        #expect(model.scheme.id == "file:Night")
        #expect(model.settings.colorSchemeId == "file:Night")

        model.settings.font = FontSetting(family: "Menlo", size: 13)
        model.notify()
        #expect(settings.fontDescription == "Menlo 13 pt")
        delegate.increaseFontSize(nil)
        #expect(settings.fontDescription == "Menlo 14 pt")
        delegate.resetFontSize(nil)
        #expect(settings.fontDescription == "Menlo 16 pt")
    }

    @Test func appCommandsValidate() throws {
        let (delegate, _) = try make()
        for name in ["toggleLightDark:", "increaseFontSize:", "decreaseFontSize:", "resetFontSize:", "showSettings:",
                     "reloadSchemes:", "openThemesFolder:", "toggleHighlightCurrentLine:"] {
            let item = NSMenuItem(title: name, action: NSSelectorFromString(name), keyEquivalent: "")
            #expect(delegate.responds(to: NSSelectorFromString(name)), "\(name)")
            #expect(delegate.validateMenuItem(item), "\(name)")
        }
        #expect(NSFontManager.shared.target === delegate.fontController)
    }
}

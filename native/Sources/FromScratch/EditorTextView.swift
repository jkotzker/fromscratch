import AppKit
import FromScratchCore

/// The scratchpad's text view. Always created with `EditorTextView(usingTextLayoutManager: true)`
/// and never asked for its `layoutManager`: one such call silently and permanently switches the
/// view to TextKit 1.
final class EditorTextView: NSTextView {
    /// Space above the first line. NSTextView's inset is symmetric (`textContainerInset.height`
    /// applies to top and bottom), but v2 pads the top and bottom differently and adds the
    /// scroll-past-end space below, so the inset carries half the total and the origin is moved.
    private var topInset: CGFloat = 0

    func setInsets(top: CGFloat, bottom: CGFloat, horizontal: CGFloat) {
        let inset = NSSize(width: horizontal, height: (top + bottom) / 2)
        guard top != topInset || inset != textContainerInset else { return }
        topInset = top
        textContainerInset = inset
        // Changing the inset does not resize the view by itself (measured in an offscreen harness);
        // without this the scroll-past-end space would lag until the next text change.
        sizeToFit()
    }

    /// Paragraph attributes for a CSS-style unitless line height: every line is exactly
    /// `lineHeightFactor x pointSize` tall, whatever the font's own ascent and descent.
    struct LineLayout {
        let paragraphStyle: NSParagraphStyle
        let lineHeight: CGFloat
    }

    static func lineLayout(for font: NSFont, lineHeightFactor: CGFloat, tabWidthInSpaces: CGFloat) -> LineLayout {
        let lineHeight = lineHeightFactor * font.pointSize
        let style = NSMutableParagraphStyle()
        // Fixed, not a multiple: lineHeightMultiple scales the font's natural height (1.2em for
        // Fira Code), which made lines 24 pt where CSS gives 20 pt at 16 pt.
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.tabStops = []
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        style.defaultTabInterval = spaceWidth * tabWidthInSpaces
        // TextKit 2 puts the extra space above the glyphs, where CSS half-leading would split it
        // and sit them about half a point higher at 16 pt. A positive `.baselineOffset` cannot correct that: measured in an
        // offscreen harness, it shrinks the line pitch by the offset (20 -> 19.6 pt), and adding
        // the offset back to the line height cancels the shift.
        return LineLayout(paragraphStyle: style, lineHeight: lineHeight)
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: super.textContainerOrigin.x, y: topInset)
    }

    /// Plain-text editing per the global constraints: no rich text, and none of the substitutions
    /// or detectors that would change what the user typed.
    func configureForPlainText() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        // Smart insert/delete adds or removes spaces around pasted words; CodeMirror never did.
        smartInsertDeleteEnabled = false
        drawsBackground = false
        // The text starts at the gutter edge, as `.cm-line` has no left padding in app.css.
        textContainer?.lineFragmentPadding = 0
    }

    // MARK: Current-line band

    /// The View › Highlight Current Line setting.
    var highlightsCurrentLine = false {
        didSet { if highlightsCurrentLine != oldValue { needsDisplay = true } }
    }

    /// The scheme's active-line colour (`--bg-1-translucent`), half transparent so the surface
    /// shows through.
    var activeLineColor: NSColor = .clear {
        didSet { if highlightsCurrentLine { needsDisplay = true } }
    }

    /// `.cm-activeLine` in app.css: drawn behind the text of each logical line holding a caret,
    /// and only while nothing is selected.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let bands = currentLineBandRects().filter { $0.intersects(rect) }
        guard !bands.isEmpty else { return }
        // The fades are sized in em so they scale with the type, as in app.css.
        let em = font?.pointSize ?? CGFloat(FontSetting.defaultSize)
        let clear = activeLineColor.withAlphaComponent(0)
        for band in bands where band.width > 0 {
            // transparent at 0, the colour from 1em to 2em before the right edge, transparent at
            // 100%. Fading to the same colour at zero alpha is what CSS's premultiplied
            // interpolation does with --bg-transparent, without a hue shift on the way.
            let fadeIn = min(em / band.width, 0.5)
            let fadeOut = max(1 - 2 * em / band.width, fadeIn)
            NSGradient(colors: [clear, activeLineColor, activeLineColor, clear],
                       atLocations: [0, fadeIn, fadeOut, 1], colorSpace: activeLineColor.colorSpace)?
                .draw(in: band, angle: 0)
        }
    }

    /// One rect per caret, in view coordinates: the whole paragraph (every wrapped visual line) from
    /// the text's leading edge to the right edge of the view, which is the `.cm-line` box (the
    /// right gutter is the line's own padding in v2). Empty when switched off or when any
    /// selected range is non-empty.
    func currentLineBandRects() -> [NSRect] {
        guard highlightsCurrentLine else { return [] }
        let ranges = selectedRanges.map(\.rangeValue)
        guard !ranges.isEmpty, ranges.allSatisfy({ $0.length == 0 }) else { return [] }
        let origin = textContainerOrigin
        var bands: [NSRect] = []
        for range in ranges {
            guard let frame = paragraphFrame(at: range.location) else { continue }
            let band = NSRect(x: origin.x, y: origin.y + frame.minY,
                              width: max(bounds.width - origin.x, 0), height: frame.height)
            if !bands.contains(band) { bands.append(band) }
        }
        return bands
    }

    /// The layout frame of the paragraph holding `offset`, in text container coordinates. Through
    /// the text layout manager, never the layout manager (TextKit 2 only).
    private func paragraphFrame(at offset: Int) -> NSRect? {
        guard let layout = textLayoutManager, let content = textContentStorage,
              let location = content.location(content.documentRange.location, offsetBy: offset) else { return nil }
        let text = string as NSString
        // The end of a paragraph with no line break after it (the end of the note) has no
        // fragment of its own: it belongs to the paragraph before it.
        var candidates = [location]
        if offset > 0, offset <= text.length,
           !CharacterSet.newlines.contains(UnicodeScalar(text.character(at: offset - 1)) ?? " "),
           let previous = content.location(location, offsetBy: -1) {
            candidates.append(previous)
        }
        for candidate in candidates {
            guard let fragment = layout.textLayoutFragment(for: candidate),
                  fragment.rangeInElement.contains(candidate) else { continue }
            if fragment.state != .layoutAvailable {
                layout.ensureLayout(for: fragment.rangeInElement)
            }
            return fragment.layoutFragmentFrame
        }
        // The empty line after a final line break, and an empty note, have no layout fragment;
        // the caret's segment still gives that line's frame.
        var frame: NSRect?
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
            frame = rect
            return false
        }
        guard var line = frame else { return nil }
        if let height = defaultParagraphStyle?.minimumLineHeight, height > line.height {
            line.size.height = height
        }
        return line
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // The band moves with the caret and disappears with a selection. The text itself lives in
        // TextKit 2's own subviews, so only this view's background is redrawn.
        if highlightsCurrentLine {
            setNeedsDisplay(visibleRect)
        }
    }

    // MARK: Font panel

    // The font manager's target is the FontController, which stores the choice. Should a choice
    // reach the text view anyway, it goes there too, so the editor never shows a font that is not
    // the stored one.
    override func changeFont(_ sender: Any?) {
        if let controller = NSFontManager.shared.target as? FontController {
            controller.changeFont(sender as? NSFontManager)
        } else {
            super.changeFont(sender)
        }
    }

    @objc func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }

    // MARK: Line commands

    @objc func toggleCheckbox(_ sender: Any?) {
        runLineCommand(Commands.undoName(.toggleCheckbox)) { TextCommands.toggleCheckbox(text: $0, selection: $1) }
    }

    @objc func deleteLine(_ sender: Any?) {
        runLineCommand(Commands.undoName(.deleteLine)) { TextCommands.deleteLines(text: $0, selection: $1) }
    }

    @objc func moveLineUp(_ sender: Any?) {
        runLineCommand(Commands.undoName(.moveLineUp)) { TextCommands.moveLines(text: $0, selection: $1, direction: .up) }
    }

    @objc func moveLineDown(_ sender: Any?) {
        runLineCommand(Commands.undoName(.moveLineDown)) { TextCommands.moveLines(text: $0, selection: $1, direction: .down) }
    }

    // Tab and ⇧Tab come from the text system's key bindings, not the menu, so they are not in the
    // command table. An empty selection gets a tab character; a selection indents its lines.
    override func insertTab(_ sender: Any?) {
        // Composition (marked text) belongs to the input method, as for Return.
        guard !isFieldEditor, !hasMarkedText() else { return super.insertTab(sender) }
        runLineCommand("Indent") { TextCommands.indent(text: $0, selection: $1) }
    }

    override func insertBacktab(_ sender: Any?) {
        guard !isFieldEditor, !hasMarkedText() else { return super.insertBacktab(sender) }
        runLineCommand("Outdent") { TextCommands.outdent(text: $0, selection: $1) }
    }

    /// A new line keeps the current line's indentation. Through the typing path, so it coalesces
    /// with the surrounding typing as a plain Return would. Composition (marked text) and anything
    /// unusual keep NSTextView's own behaviour.
    override func insertNewline(_ sender: Any?) {
        // NSTextView's own Return in a read-only view gives up first responder (measured), which
        // left a read-only note without keyboard focus; it does nothing here, like the other edits.
        guard isEditable || isFieldEditor else { return NSSound.beep() }
        guard !isFieldEditor, !hasMarkedText(), selectedRanges.count == 1 else {
            return super.insertNewline(sender)
        }
        let range = selectedRange()
        insertText(TextCommands.newlineIndent(text: string, at: range.location), replacementRange: range)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleCheckbox(_:)), #selector(deleteLine(_:)),
             #selector(moveLineUp(_:)), #selector(moveLineDown(_:)):
            // Read-only notes must not change, so the commands are unavailable rather than inert.
            return isEditable
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    private func runLineCommand(_ actionName: String, _ command: (String, [NSRange]) -> EditResult?) {
        guard isEditable, !hasMarkedText() else {
            NSSound.beep()
            return
        }
        guard let result = command(string, selectedRanges.map(\.rangeValue)) else {
            NSSound.beep()
            return
        }
        apply(result, actionName: actionName)
    }

    /// Applies a command's result as one undo step named `actionName`. The edits arrive in
    /// descending order, so each one leaves the ranges of the ones still to come untouched.
    func apply(_ result: EditResult, actionName: String) {
        // An edit that replaces nothing with nothing (Delete Line on an empty note) is no change:
        // no undo step and no write.
        let edits = result.edits.filter { $0.range.length > 0 || !$0.replacement.isEmpty }
        guard !edits.isEmpty else { return }
        // Through the content storage, never the layout manager (TextKit 2 only).
        guard let storage = textContentStorage?.textStorage else { return }
        // NSTextView expects the affected ranges in ascending order, as selectedRanges are.
        let ascending = edits.reversed()

        // With groupsByEvent, opening a group at level 0 first opens an automatic event group
        // and nests this one inside it; that group stays open until the run loop closes it, and
        // when it does not (measured: commands sent from a task, and in tests) several commands
        // end up in one undo step. Turning it off while the group is open makes this group the
        // top-level one. Inside an already open group (same event) it nests as any edit would.
        let undo = undoManager
        let groupsByEvent = undo?.groupsByEvent ?? false
        undo?.groupsByEvent = false
        defer { undo?.groupsByEvent = groupsByEvent }
        // Keeps the command out of any typing that came before or comes after it.
        breakUndoCoalescing()
        undo?.beginUndoGrouping()
        guard shouldChangeText(inRanges: ascending.map { NSValue(range: $0.range) },
                               replacementStrings: ascending.map(\.replacement)) else {
            undo?.endUndoGrouping()
            NSSound.beep()
            return
        }
        storage.beginEditing()
        for edit in edits {
            // The typing attributes carry the editor's font, paragraph style and colour, which
            // inserted text would otherwise lack in an empty note.
            storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        }
        storage.endEditing()
        didChangeText()
        undo?.setActionName(actionName)
        undo?.endUndoGrouping()
        breakUndoCoalescing()

        if let first = result.selection.first {
            selectedRanges = result.selection.map { NSValue(range: $0) }
            scrollRangeToVisible(first)
        }
    }
}

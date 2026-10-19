import AppKit

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
}

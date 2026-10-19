import AppKit

/// The go-to-line strip: a thin bar across the top of the window with one field, like v2's
/// CodeMirror goto-line panel (which this app always showed at the top). Return asks `onCommit`;
/// Esc, or focus moving elsewhere, closes it.
@MainActor
final class GoToLineBar: NSView, NSTextFieldDelegate {
    struct Style {
        /// The bar's backdrop: the scheme background, so text scrolling underneath stays hidden.
        var backdrop: NSColor
        var overlayBackground: NSColor
        var overlayText: NSColor
        var font: NSFont
    }

    // v2 on macOS: `.cm-panel.cm-dialog` padding 1.75rem on top (clear of the traffic lights) and
    // 0.5rem below (v3 uses 0.875rem below, so the field doesn't sit on the strip's bottom edge);
    // the field has a 12rem minimum width and 0.15rem 0.4rem padding.
    // 28 pt is Sequoia's titlebar; macOS 26's is 32 pt, so the field follows `titlebarHeight`.
    static let topPadding: CGFloat = 28
    static let bottomPadding: CGFloat = 14
    static let fieldMinimumWidth: CGFloat = 192

    /// Gets the field's text on Return. Returning false (invalid input) keeps the bar open.
    var onCommit: ((String) -> Bool)?
    /// Called once the bar has closed. `restoreFocus` is false when focus already went elsewhere.
    var onClose: ((_ restoreFocus: Bool) -> Void)?
    /// Called after the bar has left the window, when `isOpen` is already false.
    var onClosed: (() -> Void)?

    let field = NSTextField(string: "")
    private let label = NSTextField(labelWithString: "Go to line")
    private var leading: NSLayoutConstraint?
    private var fieldTop: NSLayoutConstraint?
    /// The window's titlebar band, measured by the editor; the field never starts inside it.
    var titlebarHeight: CGFloat = 0 {
        didSet { fieldTop?.constant = max(Self.topPadding, titlebarHeight) }
    }
    private var isClosing = false
    var style: Style? {
        didSet { applyStyle() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        // v2's field had `outline: none`; the bar itself shows where typing goes.
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityLabel("Line number, or line:column")
        label.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(field)
        let leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        let fieldTop = field.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPadding)
        NSLayoutConstraint.activate([
            leading,
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.fieldMinimumWidth),
            field.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            fieldTop,
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomPadding),
            label.firstBaselineAnchor.constraint(equalTo: field.firstBaselineAnchor),
        ])
        self.leading = leading
        self.fieldTop = fieldTop
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Go to line")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Pins the bar across the top of `container` and focuses the field, filled with `initialText`
    /// and selected, so typing replaces it (CodeMirror pre-fills the current line number too).
    func open(in container: NSView, initialText: String, slideDuration: TimeInterval = 0) {
        let isNew = superview !== container
        if isNew {
            removeFromSuperview()
            translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(self)
            NSLayoutConstraint.activate([
                leadingAnchor.constraint(equalTo: container.leadingAnchor),
                trailingAnchor.constraint(equalTo: container.trailingAnchor),
                topAnchor.constraint(equalTo: container.topAnchor),
            ])
        }
        if isNew, slideDuration > 0 {
            container.layoutSubtreeIfNeeded()
            // Slides down from above the window's edge, over whatever the top of the window held.
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = bounds.height
            slide.toValue = 0
            slide.duration = slideDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(slide, forKey: "slideDown")
        }
        isClosing = false
        field.stringValue = initialText
        // Already editing (⌃G again): making the field first responder would end that editing,
        // and the end-editing notification would close the strip.
        if field.currentEditor() == nil {
            window?.makeFirstResponder(field)
        }
        field.currentEditor()?.selectAll(nil)
    }

    var isOpen: Bool { superview != nil }

    func close(restoreFocus: Bool) {
        guard isOpen, !isClosing else { return }
        isClosing = true
        // Focus moves first, so the field ends editing while it is still in the window (the
        // resulting end-editing notification finds the bar already closing).
        onClose?(restoreFocus)
        removeFromSuperview()
        onClosed?()
    }

    override func layout() {
        super.layout()
        // `padding: 0.5rem calc(5vw - 1.4em)`, never closer to the edge than 0.5rem.
        let fontSize = style?.font.pointSize ?? 16
        leading?.constant = max(8, ((window?.frame.width ?? bounds.width) * 0.05 - 1.4 * fontSize).rounded())
    }

    private func applyStyle() {
        guard let style else { return }
        label.font = style.font.withSize(style.font.pointSize * 0.8)  // `label { font-size: 0.8em }`
        label.textColor = style.overlayText
        field.font = style.font
        field.textColor = style.overlayText
        field.backgroundColor = style.overlayBackground
        field.placeholderAttributedString = NSAttributedString(string: "line or line:column", attributes: [
            .font: style.font, .foregroundColor: style.overlayText.withAlphaComponent(0.6),
        ])
        needsDisplay = true
        needsLayout = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // The overlay tint over an opaque backdrop: the panel reads as one shade off the editor.
        guard let style else { return }
        layer?.backgroundColor = style.backdrop.blended(withFraction: style.overlayBackground.alphaComponent,
                                                         of: style.overlayBackground.withAlphaComponent(1))?.cgColor
            ?? style.backdrop.cgColor
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Invalid input beeps (the caller's job) and leaves the bar open for another try.
            if onCommit?(field.stringValue) == true {
                close(restoreFocus: true)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(restoreFocus: true)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Focus moved elsewhere (a click in the text, Tab): the strip goes away without taking
        // the focus back.
        close(restoreFocus: false)
    }
}

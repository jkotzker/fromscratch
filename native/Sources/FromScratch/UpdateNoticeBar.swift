import AppKit

/// v2's `.updater`: a full-width bar across the top of the window. It is 3rem wide-padded in CSS
/// (2rem clear of the traffic lights on macOS, then a 2rem line) and sits 1rem above the window's
/// edge, so 48 pt of it show. Clicking it opens the releases page; the round × beside the text
/// hides it until a newer version appears. It is a plain view that never takes first responder,
/// so the editor keeps the keyboard.
@MainActor
final class UpdateNoticeBar: NSView {
    struct Style {
        var background: NSColor
        var text: NSColor
        var textHover: NSColor
        var font: NSFont
    }

    // `.updater`: padding-top 2rem on darwin + line-height 2rem, top -1rem.
    static let height: CGFloat = 48
    static let lineHeight: CGFloat = 32
    // `.updater span`: 1.5rem circle, right 0.5rem, bottom 0.25rem, font-size 1.5rem.
    static let closeDiameter: CGFloat = 24
    static let closeTrailing: CGFloat = 8
    static let closeBottom: CGFloat = 4
    // Padding: 0.5rem on the left, 2.5rem on the right (room for ×).
    static let textLeading: CGFloat = 8
    static let textTrailing: CGFloat = 40

    static func message(for version: String) -> String { "There's an update available! Get version \(version)" }
    static let closeToolTip = "Don't show this again until next available update"

    let version: String
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?
    var style: Style? {
        didSet { applyStyle() }
    }

    private let label: NSTextField
    private let closeButton = CloseButton()
    private var isHovered = false

    init(version: String) {
        self.version = version
        label = NSTextField(labelWithString: Self.message(for: version))
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.toolTip = Self.closeToolTip
        closeButton.onClick = { [weak self] in self?.onDismiss?() }
        addSubview(label)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.textLeading),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.textTrailing),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.heightAnchor.constraint(equalToConstant: Self.lineHeight),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeDiameter),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.closeTrailing),
            closeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.closeBottom),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.message(for: version))
        closeButton.setAccessibilityLabel("Hide update message")
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Pins the bar across the top of `container`.
    func attach(to container: NSView) {
        container.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topAnchor.constraint(equalTo: container.topAnchor),
        ])
    }

    /// Runs the click action, for the accessibility press and the launch checks.
    func performOpen() { onOpen?() }
    func performDismiss() { onDismiss?() }

    // The first click on an inactive window should act, as a click on v2's bar did.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The bar is not part of the titlebar's drag area.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onOpen?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        applyStyle()
    }

    private func applyStyle() {
        guard let style else { return }
        label.font = style.font
        label.textColor = isHovered ? style.textHover : style.text
        closeButton.font = style.font.withSize(24)
        closeButton.hoverColor = style.textHover
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let style else { return }
        // `--overlay-bg-hover` is 0.15 ink against 0.1 at rest.
        let alpha = isHovered ? min(1, style.background.alphaComponent * 1.5) : style.background.alphaComponent
        layer?.backgroundColor = style.background.withAlphaComponent(alpha).cgColor
    }
}

/// The × in a dark disc. A click on it must not also open the releases page, so it consumes the
/// whole press.
private final class CloseButton: NSView {
    var onClick: (() -> Void)?
    var font: NSFont = .systemFont(ofSize: 24) {
        didSet { needsDisplay = true }
    }
    var hoverColor: NSColor = .white
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // rgba(0,0,0,.3) at rest, .5 on hover; the glyph rgba(255,255,255,.5), then the hover text.
        NSColor.black.withAlphaComponent(isHovered ? 0.5 : 0.3).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let glyph = NSAttributedString(string: "\u{00D7}", attributes: [
            .font: font,
            .foregroundColor: isHovered ? hoverColor : NSColor.white.withAlphaComponent(0.5),
        ])
        let size = glyph.size()
        glyph.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

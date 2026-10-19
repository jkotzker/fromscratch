import AppKit

/// A one-line message in the overlay style (`.nosave` in app.css): 2rem tall, 0.5rem padding and
/// corner radius, overlay background and text colours, centred 0.5rem above the bottom edge.
@MainActor
final class OverlayNotice: NSView {
    struct Style {
        var background: NSColor
        var text: NSColor
        var font: NSFont
    }

    /// The current scheme's overlay colours and font. The editor sets it whenever the scheme or
    /// font changes; notices on screen restyle themselves.
    static var style = Style(background: .clear, text: .secondaryLabelColor, font: .systemFont(ofSize: 16)) {
        didSet { NotificationCenter.default.post(name: styleDidChange, object: nil) }
    }
    private static let styleDidChange = Notification.Name("FromScratchOverlayStyleDidChange")

    // `.nosave`: bottom 0.5rem when shown, -4em (64 pt at 16 pt) while hidden, moved with a 0.5 s
    // cubic-bezier(0.175, 0.885, 0.32, 1.275) transition.
    static let shownInset: CGFloat = 8
    static let hiddenInset: CGFloat = -64
    static let slideDuration: TimeInterval = 0.5
    private static let slideTiming = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.275)

    let text: String
    private let label: NSTextField
    private var bottom: NSLayoutConstraint?
    private var hideTask: Task<Void, Never>?
    /// Bumped by every show, so a slide-out that a newer show interrupted does not remove the view.
    private var generation = 0

    /// Shows `text` at the bottom centre of `view`. With a duration the notice slides in and out
    /// again after that many seconds; showing the same text while it is up restarts the timer, as
    /// v2's save hint did. Without one it appears in place and stays.
    @discardableResult
    static func show(_ text: String, in view: NSView, duration: TimeInterval?) -> OverlayNotice {
        if let existing = view.subviews.lazy.compactMap({ $0 as? OverlayNotice }).first(where: { $0.text == text }) {
            existing.present(for: duration)
            return existing
        }
        let notice = OverlayNotice(text: text)
        notice.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(notice)
        let bottom = notice.bottomAnchor.constraint(
            equalTo: view.bottomAnchor, constant: -(duration == nil ? shownInset : hiddenInset))
        NSLayoutConstraint.activate([
            notice.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottom,
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
        ])
        notice.bottom = bottom
        view.layoutSubtreeIfNeeded()
        notice.present(for: duration)
        return notice
    }

    private init(text: String) {
        self.text = text
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
        applyStyle()
        // Selector-based, so the registration goes away with the view.
        NotificationCenter.default.addObserver(
            self, selector: #selector(styleChanged(_:)), name: Self.styleDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func styleChanged(_ notification: Notification) {
        applyStyle()
    }

    private func applyStyle() {
        label.font = Self.style.font
        label.textColor = Self.style.text
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Self.style.background.cgColor
    }

    private func present(for duration: TimeInterval?) {
        generation += 1
        hideTask?.cancel()
        hideTask = nil
        guard let duration else {
            bottom?.constant = -Self.shownInset
            return
        }
        slide(to: Self.shownInset)
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        let shown = generation
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.generation == shown else { return }
            self.slide(to: Self.hiddenInset) { [weak self] in
                guard let self, self.generation == shown else { return }
                self.removeFromSuperview()
            }
        }
    }

    private func slide(to inset: CGFloat, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let bottom else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            bottom.constant = -inset
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.slideDuration
            context.timingFunction = Self.slideTiming
            context.allowsImplicitAnimation = true
            bottom.animator().constant = -inset
        }, completionHandler: { MainActor.assumeIsolated { completion?() } })
    }
}

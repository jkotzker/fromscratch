import AppKit

/// A glass pill behind the close, minimise and zoom buttons. The text scrolls under the
/// transparent titlebar, and from macOS 26 the buttons sit on it with nothing between them and
/// the glyphs; the pill gives them a surface of their own. Before macOS 26 nothing is drawn and
/// the window looks as it always has.
///
/// It lives in the content view, above the text and below the drag strip, so it never takes a
/// click: the buttons are in the titlebar, above all content, and the margin around them still
/// drags the window.
@MainActor
final class WindowControlsBacking: NSView {
    /// Space between the buttons' bounding box and the pill's edge, at most. The buttons sit only
    /// a few points below the window's top edge (6 pt on macOS 27), so the padding shrinks to keep
    /// `edgeMargin` between the pill and the window's top and left edges, which keeps it clear of
    /// the rounded corner.
    static let padding = NSSize(width: 7, height: 5)
    static let edgeMargin: CGFloat = 3

    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    /// The editor surface colour (the scheme background at `--bg-translucent` alpha), laid inside
    /// the glass. The glass is not tinted: a tint toward a dark background renders near black
    /// (measured: `#1e1e1e` at 85% drew 0,0,0 against a 34,34,34 window body), while the surface
    /// over untinted glass repeats the window's own composition (scheme surface over a system
    /// material) and drew 33,33,33.
    var surface: NSColor? {
        didSet { applySurface() }
    }

    /// The NSGlassEffectView, once `activate()` has added it.
    private(set) var glass: NSView?
    private var observers: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Whether this system draws the pill at all.
    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Adds the (still empty) view to `container` and follows the buttons from then on: the
    /// titlebar moves them itself (its height changes between releases, and on leaving full
    /// screen), so their frames are watched rather than predicted.
    func attach(to container: NSView, in window: NSWindow) {
        // Pinned to the top-left corner, where the buttons are.
        autoresizingMask = container.isFlipped ? [.maxXMargin, .maxYMargin] : [.maxXMargin, .minYMargin]
        container.addSubview(self)
        guard Self.isSupported else { return }
        for type in Self.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            button.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: button, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            })
        }
    }

    /// Adds the glass and shows the pill. Called once the window is on screen: with a glass view
    /// in the content view while the window is still being built, the window defers placing its
    /// content view, and the editor's first titlebar measurement (contentLayoutRect converted
    /// into the content view) reads the whole window height.
    func activate() {
        if #available(macOS 26, *), glass == nil {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            addSubview(glass)
            self.glass = glass
            applySurface()
        }
        reposition()
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Fits the pill around the visible buttons. Hidden until activated, and in full screen,
    /// where the titlebar and its buttons slide in over the top of the screen on their own.
    func reposition() {
        guard glass != nil, let window, let container = superview,
              !window.styleMask.contains(.fullScreen) else {
            isHidden = true
            return
        }
        let frames = Self.buttonTypes.compactMap { type -> NSRect? in
            guard let button = window.standardWindowButton(type), !button.isHidden,
                  let parent = button.superview else { return nil }
            return container.convert(button.frame, from: parent)
        }
        guard let first = frames.first else {
            isHidden = true
            return
        }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let pill = Self.pillFrame(around: union, in: container.bounds, flipped: container.isFlipped)
        if frame != pill { frame = pill }
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.cornerRadius = pill.height / 2
        }
        isHidden = false
    }

    /// The pill around `buttons`, kept `edgeMargin` inside the top and left edges of `bounds`,
    /// with the horizontal padding never more than 2 pt over the vertical.
    static func pillFrame(around buttons: NSRect, in bounds: NSRect, flipped: Bool) -> NSRect {
        let topGap = flipped ? buttons.minY - bounds.minY : bounds.maxY - buttons.maxY
        let leftGap = buttons.minX - bounds.minX
        let vertical = max(0, min(padding.height, topGap - edgeMargin))
        let horizontal = max(0, min(padding.width, vertical + 2, leftGap - edgeMargin))
        return buttons.insetBy(dx: -horizontal, dy: -vertical).integral
    }

    private func applySurface() {
        guard #available(macOS 26, *), let glass = glass as? NSGlassEffectView else { return }
        let fill = glass.contentView ?? {
            let view = NSView()
            view.wantsLayer = true
            glass.contentView = view
            return view
        }()
        fill.layer?.backgroundColor = surface?.cgColor
    }

    // The buttons above it and the drag strip around it take every click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

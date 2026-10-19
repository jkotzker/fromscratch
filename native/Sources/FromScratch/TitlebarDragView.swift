import AppKit

/// What a double-click on a titlebar does, from the system setting (Desktop & Dock › "Double-click
/// a window's title bar to"). The real titlebar reads the same defaults.
enum TitlebarDoubleClickAction: Equatable {
    case zoom, minimize, none

    static func current(_ defaults: UserDefaults = .standard) -> TitlebarDoubleClickAction {
        resolve(action: defaults.string(forKey: "AppleActionOnDoubleClick"),
                miniaturize: defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"))
    }

    static func resolve(action: String?, miniaturize: Bool) -> TitlebarDoubleClickAction {
        switch action {
        case "Minimize"?: return .minimize
        case "None"?: return .none
        // "Maximize" is the default; "Fill" and anything newer act as zoom, which here fills the
        // screen's visible frame as well.
        case .some: return .zoom
        // Unset: older systems stored only this switch.
        case nil: return miniaturize ? .minimize : .zoom
        }
    }

    @MainActor
    func perform(on window: NSWindow) {
        switch self {
        case .zoom: window.performZoom(nil)
        case .minimize: window.performMiniaturize(nil)
        case .none: break
        }
    }
}

/// A taller grab area along the top of the window. The transparent titlebar is only 28 pt, and the
/// text's 48 pt top inset left the band below it looking draggable while it selected text instead.
/// This view sits above the text and below the go-to-line strip and the update bar, moves the
/// window on a drag and runs the titlebar's double-click action, as the titlebar itself does.
@MainActor
final class TitlebarDragView: NSView {
    /// Just under the editor's 48 pt top inset, so the first line stays clickable.
    static let height: CGFloat = 40

    /// Rects in this view's coordinates that keep their own clicks: the find bar, which lives in
    /// the scroll view underneath.
    var excludedRects: () -> [NSRect] = { [] }
    /// The system setting, read at each double-click so a change applies at once. Tests replace it.
    var doubleClickAction: () -> TitlebarDoubleClickAction = { .current() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Pins the strip across the top of `container`.
    func attach(to container: NSView) {
        frame = NSRect(x: 0, y: container.bounds.maxY - Self.height, width: container.bounds.width, height: Self.height)
        autoresizingMask = container.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
        container.addSubview(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // A full-screen window neither moves nor zooms, so the text gets those clicks back.
        guard !isHidden, window?.styleMask.contains(.fullScreen) != true, bounds.contains(local),
              !excludedRects().contains(where: { $0.contains(local) }) else {
            return nil
        }
        return self
    }

    // Like the titlebar, a click on an inactive window both activates it and starts the drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The drag is done explicitly in mouseDown; letting AppKit also treat the press as a window
    // background drag would only make it depend on isMovableByWindowBackground.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 {
            doubleClickAction().perform(on: window)
        } else {
            window.performDrag(with: event)
        }
    }
}

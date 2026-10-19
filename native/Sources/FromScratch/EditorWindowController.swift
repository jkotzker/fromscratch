import AppKit
import FromScratchCore

/// The single scratchpad window: vibrancy, the scheme's translucent surface, and the editor.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    // createWindow in src/main/index.js: 550x450 by default, never smaller than 300x200.
    static let defaultSize = NSSize(width: 550, height: 450)
    static let minimumSize = NSSize(width: 300, height: 200)

    // `.cm-content` padding is 3rem 0 4rem; `.cm-gutters` and `.cm-line` padding-right are 5vw.
    static let topInset: CGFloat = 48
    static let bottomInset: CGFloat = 64
    static let horizontalInsetFraction: CGFloat = 0.05
    // `line-height: 1.25` on body, which CodeMirror inherits. Unitless CSS line height is a factor
    // of the font size (20 pt at 16 pt), not of the font's natural line height.
    static let lineHeightFactor: CGFloat = 1.25
    // EditorState.tabSize.of(4) in src/renderer/src/editor/extensions.js.
    static let tabWidthInSpaces: CGFloat = 4

    static let readOnlyNotice = "This note isn't valid UTF-8, so FromScratch opened it read-only to protect it."

    private let model: AppModel
    private let surfaceView = SurfaceView()
    private let scrollView = NSScrollView()
    let textView = EditorTextView(usingTextLayoutManager: true)
    private var notice: NoticeView?
    private var lineHeight: CGFloat = 20
    /// From willEnter until didExit: full screen is not persisted, as in v2.
    private var fullScreenActive = false
    /// Set once the window closes: quitting follows, and a closed window's frame no longer says
    /// whether it was zoomed, so the state stored at close must not be overwritten.
    private var didClose = false
    /// The frame a zoom is animating to. The animation's intermediate frames are neither the old
    /// frame nor the zoomed one, so nothing is stored until it settles.
    private var zoomTarget: NSRect?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "FromScratch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = Self.minimumSize
        // v2 is a single-window app; window tabs would only offer an empty Merge All Windows.
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)

        restoreFrame(of: window)
        buildViews(in: window)
        loadContent()
        applyFont()
        applyScheme()
        model.didChange.append { [weak self] in
            self?.applyFont()
            self?.applyScheme()
        }
        // After the frame is restored, so restoring it does not count as a user move.
        window.delegate = self

        #if DEBUG
        assert(textView.textLayoutManager != nil, "The editor fell back to TextKit 1")
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        guard let window else { return }
        showWindow(nil)
        // v2 maximized after showing (ready-to-show in src/main/index.js); on macOS that is zoom.
        if model.settings.windowState.isMaximized, !window.isZoomed {
            window.zoom(nil)
        }
        window.makeFirstResponder(textView)
    }

    // MARK: Building

    private func restoreFrame(of window: NSWindow) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let saved = WindowGeometry.restoredFrame(
            saved: model.settings.windowState.bounds,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            primaryHeight: primaryHeight)
        if var frame = saved {
            frame.size.width = max(frame.size.width, Self.minimumSize.width)
            frame.size.height = max(frame.size.height, Self.minimumSize.height)
            window.setFrame(frame, display: false)
        } else {
            window.setFrame(NSRect(origin: .zero, size: Self.defaultSize), display: false)
            window.center()
        }
    }

    private func buildViews(in window: NSWindow) {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        window.contentView = effect

        surfaceView.frame = effect.bounds
        surfaceView.autoresizingMask = [.width, .height]
        effect.addSubview(surfaceView)

        scrollView.frame = effect.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // The text runs under the transparent titlebar; the 3rem top inset keeps it clear, as in v2.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        effect.addSubview(scrollView)

        let contentSize = scrollView.contentSize
        textView.configureForPlainText()
        textView.delegate = self
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // Soft wrap: the container follows the view's width.
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
    }

    private func loadContent() {
        textView.string = model.content.initialText
        guard model.content.isReadOnly, let content = window?.contentView else { return }
        textView.isEditable = false
        let notice = NoticeView(text: Self.readOnlyNotice)
        notice.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(notice)
        // Placed like `.nosave.active` in app.css: centred, 0.5rem above the bottom edge.
        NSLayoutConstraint.activate([
            notice.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            notice.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 8),
        ])
        self.notice = notice
    }

    // MARK: Appearance

    private func applyFont() {
        let font = Fonts.font(for: model.settings.font)
        let layout = EditorTextView.lineLayout(
            for: font, lineHeightFactor: Self.lineHeightFactor, tabWidthInSpaces: Self.tabWidthInSpaces)
        let style = layout.paragraphStyle

        textView.font = font
        textView.defaultParagraphStyle = style
        // Through the content storage, never the layout manager (TextKit 2 only).
        if let storage = textView.textContentStorage?.textStorage, storage.length > 0 {
            storage.beginEditing()
            let all = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.paragraphStyle, value: style, range: all)
            storage.endEditing()
        }
        var typing = textView.typingAttributes
        typing[.font] = font
        typing[.paragraphStyle] = style
        textView.typingAttributes = typing
        lineHeight = layout.lineHeight
        // `.nosave` inherits the body font at the 16px root size.
        notice?.font = Fonts.font(for: FontSetting(family: model.settings.font.family, size: 16,
                                                   face: model.settings.font.face))
        layoutEditor()
    }

    /// Colours this task needs to render: surface, text, caret. Selection and the current-line band
    /// are Task 10.
    private func applyScheme() {
        let scheme = model.scheme
        let palette = scheme.palette
        surfaceView.color = NSColor(declared: scheme.colors.background, alpha: CGFloat(palette.surface.alpha))
        let text = NSColor(declared: scheme.colors.foreground)
        textView.textColor = text
        textView.insertionPointColor = scheme.colors.cursor.map { NSColor(declared: $0) }
            ?? NSColor(srgb: palette.cursor)
        textView.typingAttributes[.foregroundColor] = text
        notice?.apply(background: NSColor(srgb: palette.overlayBackground), text: NSColor(srgb: palette.overlayText))
    }

    /// Insets that depend on the window size: the 5vw gutters and the scroll-past-end space.
    private func layoutEditor() {
        guard let window else { return }
        let visibleHeight = scrollView.contentSize.height
        // Scroll past the end: the last line can be scrolled up to the top of the view. The CSS
        // bottom padding still applies when the window is too short for that to exceed it.
        let bottom = max(Self.bottomInset, visibleHeight - lineHeight)
        // Fill the visible area so a click below the last line still lands in the editor. Set
        // first: setInsets resizes the view to fit, which honours minSize.
        textView.minSize = NSSize(width: 0, height: visibleHeight)
        textView.setInsets(
            top: Self.topInset, bottom: bottom,
            horizontal: (window.frame.width * Self.horizontalInsetFraction).rounded())
    }

    // MARK: Saving

    func textDidChange(_ notification: Notification) {
        model.content.scheduleWrite(textView.string)
    }

    /// Mirrors storeWindowState in src/main/index.js: bounds are only updated while not maximized,
    /// so un-zooming after a relaunch returns to the last ordinary frame.
    func storeWindowState() {
        guard let window, !didClose, zoomTarget == nil, !fullScreenActive,
              !window.styleMask.contains(.fullScreen) else { return }
        var state = model.settings.windowState
        state.isMaximized = window.isZoomed
        if !state.isMaximized, let primary = NSScreen.screens.first {
            state.bounds = WindowGeometry.electronBounds(appKit: window.frame, primaryHeight: primary.frame.height)
        }
        if state != model.settings.windowState {
            model.settings.windowState = state
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        zoomTarget = newFrame
        // Fallback in case the final frame never matches the target exactly.
        let settle = window.animationResizeTime(newFrame) + 0.1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            self?.zoomSettled()
        }
        return true
    }

    private func zoomSettled() {
        guard zoomTarget != nil else { return }
        zoomTarget = nil
        storeWindowState()
    }

    func windowDidResize(_ notification: Notification) {
        layoutEditor()
        if let target = zoomTarget, window?.frame == target {
            zoomSettled()
        } else {
            storeWindowState()
        }
    }

    func windowDidMove(_ notification: Notification) {
        storeWindowState()
    }

    func windowWillClose(_ notification: Notification) {
        storeWindowState()
        didClose = true
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenActive = true
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        fullScreenActive = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenActive = false
        storeWindowState()
    }

    // MARK: Debug hooks

    #if DEBUG
    /// Appends `text` at the end through the same path as typing (NSTextInputClient insertText,
    /// then textDidChange, then scheduleWrite). For launch checks without GUI access.
    func debugAppend(_ text: String) {
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText(text, replacementRange: textView.selectedRange())
        NSLog("FROMSCRATCH_DEBUG appended %ld UTF-16 units; pending write: %@; TextKit 2: %@",
              (text as NSString).length,
              model.content.hasPendingWrite ? "yes" : "no",
              textView.textLayoutManager != nil ? "yes" : "no")
    }
    #endif
}

/// The editor surface: the scheme background at `--bg-translucent` alpha over the vibrancy.
private final class SurfaceView: NSView {
    var color: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
    }
}

/// A one-line message in the overlay style (`.nosave` in app.css): 2rem tall, 0.5rem padding and
/// corner radius, overlay background and text colours.
private final class NoticeView: NSView {
    private let label: NSTextField
    private var background: NSColor = .clear

    var font: NSFont? {
        get { label.font }
        set { label.font = newValue }
    }

    init(text: String) {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(background: NSColor, text: NSColor) {
        self.background = background
        label.textColor = text
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = background.cgColor
    }
}

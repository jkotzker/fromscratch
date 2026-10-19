import AppKit
#if DEBUG
import CryptoKit
#endif
import FromScratchCore

/// The single scratchpad window: vibrancy, the scheme's translucent surface, and the editor.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    // createWindow in src/main/index.js: 550x450 by default, never smaller than 300x200.
    static let defaultSize = NSSize(width: 550, height: 450)
    static let minimumSize = NSSize(width: 300, height: 200)

    // `.cm-content` padding is 3rem 0 4rem; `.cm-gutters` and `.cm-line` padding-right are 5vw.
    // The top inset is measured from the window's top edge, titlebar included.
    static let topInset: CGFloat = 48
    static let bottomInset: CGFloat = 64
    static let horizontalInsetFraction: CGFloat = 0.05
    // `line-height: 1.25` on body, which CodeMirror inherits. Unitless CSS line height is a factor
    // of the font size (20 pt at 16 pt), not of the font's natural line height.
    static let lineHeightFactor: CGFloat = 1.25
    // EditorState.tabSize.of(4) in src/renderer/src/editor/extensions.js.
    static let tabWidthInSpaces: CGFloat = 4

    static let readOnlyNotice = "This note isn't valid UTF-8, so FromScratch opened it read-only to protect it."
    // The `.nosave` hint in App.jsx, shown for 1 s after ⌘S.
    static let savedNotice = "Already saved! ;)"
    static let savedNoticeDuration: TimeInterval = 1
    static let saveFailedNotice = "Could not save your note."
    static let saveFailedNoticeDuration: TimeInterval = 2

    let model: AppModel
    private let surfaceView = SurfaceView()
    let scrollView = EditorScrollView()
    let dragStrip = TitlebarDragView()
    let textView = EditorTextView(usingTextLayoutManager: true)
    private let goToLineBar = GoToLineBar()
    private(set) var updateBar: UpdateNoticeBar?
    private var updateCheckStarted = false
    /// True while the find bar or the go-to-line strip is open: they take the update bar's place
    /// until closed. Not a dismissal, so `hiddenUpdateVersion` is never touched.
    private(set) var isUpdateBarSuppressed = false
    /// Off in tests, which need the end state synchronously.
    var animatesChrome = true
    static let chromeAnimationDuration: TimeInterval = 0.18
    private var escapeMonitor: Any?
    private var lineHeight: CGFloat = 20
    /// From willEnter until didExit: full screen is not persisted, as in v2.
    private var fullScreenActive = false
    /// From willExit until didExit, so a second Esc during the animation does not re-enter.
    private var fullScreenExiting = false
    /// Set once the window closes: quitting follows, and a closed window's frame no longer says
    /// whether it was zoomed, so the state stored at close must not be overwritten.
    private var didClose = false
    /// The frame a zoom is animating to. The animation's intermediate frames are neither the old
    /// frame nor the zoomed one, so nothing is stored until it settles.
    private var zoomTarget: NSRect?
    /// Called at the end of windowWillClose; the app delegate quits from it.
    var onClose: (@MainActor () -> Void)?

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
        // The frame comes only from settings.json, as in v2; state restoration would otherwise
        // reapply a frame of its own after restoreFrame.
        window.isRestorable = false
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
        configureGoToLineBar()
        installEscapeMonitor()

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
        startUpdateCheck()
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
        // The text scrolls under the transparent titlebar, but the scroll view's top inset is the
        // titlebar's height (layoutEditor), so the find bar, which NSScrollView places just below
        // that inset, opens under the traffic lights rather than behind them. Set by hand from
        // contentLayoutRect rather than automatically, so the text inset can be derived from the
        // same number in the same pass.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        effect.addSubview(scrollView)
        scrollView.onFindBarChange = { [weak self] in
            self?.syncUpdateBarVisibility()
            self?.layoutEditor()
        }
        // Above the text; the go-to-line strip and the update bar are added later, so above it.
        dragStrip.attach(to: effect)
        dragStrip.excludedRects = { [weak self] in self?.findBarRect(in: self?.dragStrip).map { [$0] } ?? [] }

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
        OverlayNotice.show(Self.readOnlyNotice, in: content, duration: nil)
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
        updateOverlayStyles()
        layoutEditor()
        // The band's height and fades follow the font.
        textView.needsDisplay = true
    }

    /// Surface, text, caret, selection and the current-line band. Colours the scheme file declares
    /// keep their declared space; the ones derived from it are sRGB, as the palette maths is.
    private func applyScheme() {
        let scheme = model.scheme
        let palette = scheme.palette
        surfaceView.color = NSColor(declared: scheme.colors.background, alpha: CGFloat(palette.surface.alpha))
        let text = NSColor(declared: scheme.colors.foreground)
        textView.textColor = text
        textView.insertionPointColor = scheme.colors.cursor.map { NSColor(declared: $0) }
            ?? NSColor(srgb: palette.cursor)
        textView.typingAttributes[.foregroundColor] = text
        // --selection and --selected-text: the scheme's Selection and Selected Text colours, else a
        // mix toward the text and the text colour itself (derivePalette).
        textView.selectedTextAttributes = [
            .backgroundColor: scheme.colors.selection.map { NSColor(declared: $0) } ?? NSColor(srgb: palette.selection),
            .foregroundColor: NSColor(declared: scheme.colors.selectedText ?? scheme.colors.foreground),
        ]
        textView.activeLineColor = NSColor(srgb: palette.activeLine)
        textView.highlightsCurrentLine = model.settings.highlightCurrentLine
        updateOverlayStyles()
    }

    /// The notice and the go-to-line strip use the overlay colours. `.nosave` inherits the body
    /// font at the 16px root size; the goto-line panel inherits the editor's font and size.
    private func updateOverlayStyles() {
        let scheme = model.scheme
        let palette = scheme.palette
        let overlayBackground = NSColor(srgb: palette.overlayBackground)
        let overlayText = NSColor(srgb: palette.overlayText)
        let setting = model.settings.font
        OverlayNotice.style = OverlayNotice.Style(
            background: overlayBackground, text: overlayText,
            font: Fonts.font(for: FontSetting(family: setting.family, size: 16, face: setting.face)))
        updateBar?.style = updateBarStyle()
        goToLineBar.style = GoToLineBar.Style(
            backdrop: NSColor(declared: scheme.colors.background), overlayBackground: overlayBackground,
            overlayText: overlayText, font: textView.font ?? Fonts.font(for: setting))
    }

    private func updateBarStyle() -> UpdateNoticeBar.Style {
        let palette = model.scheme.palette
        let setting = model.settings.font
        return UpdateNoticeBar.Style(
            backdrop: NSColor(declared: model.scheme.colors.background),
            background: NSColor(srgb: palette.overlayBackground), text: NSColor(srgb: palette.overlayText),
            textHover: NSColor(srgb: palette.overlayTextHover),
            font: Fonts.font(for: FontSetting(family: setting.family, size: 16, face: setting.face)))
    }

    // MARK: Update notice

    /// The version in Info.plist; an unbundled debug run has none, so it reports the release it builds.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.0"
    }

    /// Once per launch, after the window shows: asks GitHub off the main thread and, only when the
    /// answer is newer and not the version the user already dismissed, shows the bar. Never reports
    /// a failure (v2's getNewerVersion).
    private func startUpdateCheck() {
        guard !updateCheckStarted else { return }
        updateCheckStarted = true
        var override: String?
        #if DEBUG
        override = ProcessInfo.processInfo.environment["FROMSCRATCH_DEBUG_LATEST_TAG"]
        #endif
        let fixedTag = override
        Task { [weak self] in
            let tag: String?
            if let fixedTag {
                tag = fixedTag
            } else {
                tag = await UpdateCheck.fetchLatestTag(session: .shared)
            }
            guard let self, let tag,
                  let version = UpdateCheck.newerVersion(latestTag: tag, current: Self.currentVersion),
                  version != self.model.settings.hiddenUpdateVersion else { return }
            self.showUpdateBar(version: version)
        }
    }

    func showUpdateBar(version: String) {
        guard !didClose, updateBar == nil, let content = window?.contentView else { return }
        let bar = UpdateNoticeBar(version: version)
        bar.style = updateBarStyle()
        bar.onOpen = { [weak self] in
            NSWorkspace.shared.open(UpdateCheck.releasesPage)
            self?.hideUpdateBar()
        }
        bar.onDismiss = { [weak self] in
            self?.model.settings.hiddenUpdateVersion = version
            self?.hideUpdateBar()
        }
        bar.attach(to: content)
        updateBar = bar
        bar.isHidden = isUpdateBarSuppressed
        content.layoutSubtreeIfNeeded()
        layoutEditor()
    }

    /// Whether the find bar or the go-to strip is open, so the update bar gives way to it.
    private var isTopBarOpen: Bool { isFindBarShowing || goToLineBar.isOpen }

    private func syncUpdateBarVisibility() {
        let suppress = isTopBarOpen
        guard suppress != isUpdateBarSuppressed else { return }
        isUpdateBarSuppressed = suppress
        guard let bar = updateBar else { return }
        // The text clears the update bar only while it shows. (Without one, the insets are
        // untouched, so opening the strip never moves the scroll position.)
        layoutEditor()
        let animate = animatesChrome && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && window?.isVisible == true
        guard animate else {
            bar.layer?.removeAllAnimations()
            bar.alphaValue = 1
            bar.isHidden = suppress
            return
        }
        // The system find bar cannot be animated, so the update bar fades out as it appears; the
        // go-to strip slides down over it meanwhile.
        if suppress {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.chromeAnimationDuration
                bar.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak bar] in
                MainActor.assumeIsolated {
                    guard let self, let bar, self.isUpdateBarSuppressed else { return }
                    bar.isHidden = true
                    bar.alphaValue = 1
                }
            })
        } else {
            bar.alphaValue = 0
            bar.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.chromeAnimationDuration
                bar.animator().alphaValue = 1
            }
        }
    }

    private func hideUpdateBar() {
        updateBar?.removeFromSuperview()
        updateBar = nil
        layoutEditor()
    }

    /// The height of the titlebar band at the top of the full-size content view: the part
    /// `contentLayoutRect` leaves out. 0 in full screen, where the titlebar is hidden.
    static func titlebarHeight(of window: NSWindow) -> CGFloat {
        guard let content = window.contentView else { return 0 }
        let layout = content.convert(window.contentLayoutRect, from: nil)
        return max(0, content.bounds.maxY - layout.maxY)
    }

    /// Insets that depend on the window: the titlebar, the 5vw gutters and the scroll-past-end space.
    private func layoutEditor() {
        guard let window else { return }
        let titlebar = Self.titlebarHeight(of: window)
        if scrollView.contentInsets.top != titlebar {
            scrollView.contentInsets = NSEdgeInsets(top: titlebar, left: 0, bottom: 0, right: 0)
        }
        // NSScrollView lays the find bar over the document, just below the top inset (measured:
        // with a 60 pt inset it moved to 60 pt and still covered the text). The text moves down
        // by the bar's height instead, so no line hides behind it.
        let findBar = findBarHeight
        // The update bar covers the top 56 pt of the window; the text clears whichever bar reaches
        // lower, with the same gap (topInset - titlebar) the find bar leaves.
        let bandBottom = max(titlebar + findBar, updateBar == nil || isUpdateBarSuppressed ? 0 : UpdateNoticeBar.height)
        let firstLineTop = bandBottom + max(0, Self.topInset - titlebar)
        // The clip view still spans the whole window; the inset only offsets the document.
        let fullHeight = scrollView.contentSize.height
        // Scroll past the end: the last line can be scrolled up to the top of the window, as
        // before the titlebar inset. The CSS bottom padding still applies when the window is too
        // short for that to exceed it.
        let bottom = max(Self.bottomInset, fullHeight - lineHeight)
        // Fill the area below the titlebar so a click below the last line still lands in the
        // editor. Set first: setInsets resizes the view to fit, which honours minSize.
        textView.minSize = NSSize(width: 0, height: max(0, fullHeight - titlebar))
        // The document starts below the titlebar, so the text keeps its 48 pt from the window top.
        textView.setInsets(
            top: max(0, firstLineTop - titlebar), bottom: bottom,
            horizontal: (window.frame.width * Self.horizontalInsetFraction).rounded())
    }

    private var isFindBarShowing: Bool {
        guard scrollView.isFindBarVisible, let bar = scrollView.findBarView else { return false }
        return !bar.isHidden
    }

    private var findBarHeight: CGFloat {
        guard isFindBarShowing, let bar = scrollView.findBarView else { return 0 }
        return bar.frame.height
    }

    /// The find bar's frame in `view`'s coordinates, while it is showing.
    func findBarRect(in view: NSView?) -> NSRect? {
        guard let view, scrollView.isFindBarVisible, let bar = scrollView.findBarView, bar.superview != nil,
              !bar.isHidden else { return nil }
        return view.convert(bar.bounds, from: bar)
    }

    /// Where the first line's top edge is, measured down from the window's top edge.
    func firstLineTopFromWindowTop() -> CGFloat? {
        guard let window, let content = window.contentView, let frame = textView.paragraphFrame(at: 0) else {
            return nil
        }
        let top = NSPoint(x: 0, y: textView.textContainerOrigin.y + frame.minY)
        return content.bounds.maxY - content.convert(top, from: textView).y
    }

    // MARK: Commands

    /// ⌘S: the note is saved continuously, so this writes anything still pending and says so.
    @objc func saveNow(_ sender: Any?) {
        // A read-only note is never written; its own notice already explains why.
        guard !model.content.isReadOnly else {
            NSSound.beep()
            return
        }
        model.content.flush()
        guard let content = window?.contentView else { return }
        if model.content.hasPendingWrite {
            // The write failed and the text is only in memory: do not claim it was saved.
            NSSound.beep()
            OverlayNotice.show(Self.saveFailedNotice, in: content, duration: Self.saveFailedNoticeDuration)
        } else {
            OverlayNotice.show(Self.savedNotice, in: content, duration: Self.savedNoticeDuration)
        }
    }

    /// ⌃G: opens the strip (or refocuses it), pre-filled with the caret's line number.
    @objc func showGoToLine(_ sender: Any?) {
        guard let content = window?.contentView else { return }
        let line = Self.lineNumber(at: textView.selectedRange().location, in: textView.string as NSString)
        // Slide down only on the way in, and not when ⌃G just refocuses an open strip.
        let slide = !goToLineBar.isOpen && animatesChrome && window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        goToLineBar.open(in: content, initialText: String(line), slideDuration: slide ? Self.chromeAnimationDuration : 0)
        syncUpdateBarVisibility()
    }

    var isGoToLineOpen: Bool { goToLineBar.isOpen }

    private func configureGoToLineBar() {
        goToLineBar.onCommit = { [weak self] input in
            guard let self else { return false }
            guard let target = TextCommands.parseGoToLine(input, text: self.textView.string) else {
                NSSound.beep()
                return false
            }
            self.textView.setSelectedRange(target)
            // Only a committed jump scrolls: when the strip closes because a click moved focus,
            // scrolling would move the text out from under that click.
            self.textView.scrollRangeToVisible(target)
            return true
        }
        goToLineBar.onClose = { [weak self] restoreFocus in
            guard let self, restoreFocus else { return }
            self.window?.makeFirstResponder(self.textView)
        }
        goToLineBar.onClosed = { [weak self] in self?.syncUpdateBarVisibility() }
    }

    /// 1-based line of `location`, counting lines the way `TextCommands.parseGoToLine` does: a
    /// terminated last line is followed by an empty one.
    static func lineNumber(at location: Int, in text: NSString) -> Int {
        var number = 1
        var start = 0
        while start < text.length {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            if location < end || end == contentsEnd { break }
            number += 1
            start = end
        }
        return number
    }

    /// Esc leaves full screen, as in v2 (index.js handled it in before-input-event without
    /// preventing the default). Done before dispatch rather than in `cancelOperation:` because the
    /// window answers `cancelOperation:` before its controller and the find field consumes Esc, so
    /// a responder-chain handler is never reached from either.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.leaveFullScreenOnEscape(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event should go no further.
    private func leaveFullScreenOnEscape(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode == 53, modifiers.isEmpty, let window, event.window === window,
              window.styleMask.contains(.fullScreen), fullScreenActive, !fullScreenExiting else { return false }
        let responder = window.firstResponder
        // Esc during input-method composition belongs to the input method.
        if let editor = responder as? NSTextView, editor.hasMarkedText() { return false }
        window.toggleFullScreen(nil)
        // The find field and the go-to-line field still get the key, so they close as well. The
        // editor has no Esc behaviour of its own, and the window's would act on full screen again.
        return responder === textView
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
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        onClose?()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenActive = true
    }

    // The titlebar band disappears in full screen and returns on exit; the insets follow it.
    func windowDidEnterFullScreen(_ notification: Notification) {
        layoutEditor()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        fullScreenActive = false
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        fullScreenExiting = true
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        fullScreenExiting = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenActive = false
        fullScreenExiting = false
        layoutEditor()
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

    /// Sets the selection from `loc,len[;loc,len...]`.
    func debugSelect(_ spec: String) {
        let ranges = spec.split(separator: ";").compactMap { part -> NSValue? in
            let numbers = part.split(separator: ",").compactMap { Int($0) }
            guard numbers.count == 2 else { return nil }
            return NSValue(range: NSRange(location: numbers[0], length: numbers[1]))
        }
        guard !ranges.isEmpty else { return }
        textView.selectedRanges = ranges
        NSLog("FROMSCRATCH_DEBUG selected %@; %@", spec, debugState())
    }

    /// One line describing the scheme, colours (with their colour spaces), font and band, plus
    /// the band's rendered alpha at its left edge and middle (drawn offscreen with cacheDisplay).
    func debugAppearance() -> String {
        func describe(_ color: Any?) -> String {
            guard let color = color as? NSColor else { return "-" }
            var components = [CGFloat](repeating: 0, count: color.numberOfComponents)
            color.getComponents(&components)
            return "\(color.colorSpace.localizedName ?? "?")(\(components.map { String(format: "%.3f", $0) }.joined(separator: ",")))"
        }
        let bands = textView.currentLineBandRects()
        var rendered = "-"
        if let band = bands.first, let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / textView.bounds.width
            func alpha(_ x: CGFloat) -> String {
                let c = rep.colorAt(x: Int(x * scale), y: Int(band.midY * scale))
                return c.map { String(format: "%.3f", $0.alphaComponent) } ?? "?"
            }
            rendered = "edge=\(alpha(band.minX + 0.5)) middle=\(alpha(band.midX))"
        }
        let style = textView.defaultParagraphStyle
        return """
            scheme=\(model.scheme.id) stored=\(model.settings.colorSchemeId) isDark=\(model.scheme.isDark) \
            appAppearance=\(NSApp.appearance?.name.rawValue ?? "-") \
            windowAppearance=\(window?.effectiveAppearance.name.rawValue ?? "-") \
            surface=\(describe(surfaceView.color)) text=\(describe(textView.textColor)) \
            cursor=\(describe(textView.insertionPointColor)) \
            selection=\(describe(textView.selectedTextAttributes[.backgroundColor])) \
            selectedText=\(describe(textView.selectedTextAttributes[.foregroundColor])) \
            activeLine=\(describe(textView.activeLineColor)) highlight=\(textView.highlightsCurrentLine) \
            bands=\(bands.map { NSStringFromRect($0) }) bandAlpha[\(rendered)] \
            font=\(textView.font?.fontName ?? "-") \(textView.font?.pointSize ?? 0)pt \
            lineHeight=\(style?.minimumLineHeight ?? 0)/\(style?.maximumLineHeight ?? 0) \
            inset=\(NSStringFromSize(textView.textContainerInset))
            """
    }

    /// The view a click would reach on the close button and in the middle of the window at 10, 35
    /// and 45 pt from the top.
    func debugHits() -> String {
        guard let content = window?.contentView, let frame = window?.contentView?.superview else { return "-" }
        // 20,14 is the close button.
        let points = [(20.0, 14.0), (content.bounds.midX, 10.0), (content.bounds.midX, 35.0), (content.bounds.midX, 45.0)]
        return points.map { x, fromTop in
            // The frame view is the root, so hitTest takes window coordinates.
            let point = content.convert(NSPoint(x: x, y: content.bounds.maxY - fromTop), to: nil)
            let hit = frame.hitTest(point).map { String(describing: type(of: $0)) } ?? "nil"
            return "\(Int(x)),\(Int(fromTop)):\(hit)"
        }.joined(separator: ",")
    }

    /// Clicks the update bar's ×, as a user would; false when no bar is showing.
    func debugDismissUpdate() -> Bool {
        guard let bar = updateBar else { return false }
        bar.performDismiss()
        return true
    }

    /// One line describing what the checks look at. The note itself is never logged, even in a
    /// debug build: its UTF-16 length and the first 16 hex digits of the SHA-256 of its UTF-8
    /// bytes are enough to compare against an expected text.
    func debugState() -> String {
        let selection = textView.selectedRanges.map { "\($0.rangeValue.location),\($0.rangeValue.length)" }
        let text = textView.string
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(
            format: "textLength=%ld textSHA256=%@ selection=%@ undo=%@ undoLevel=%ld firstResponder=%@ goToLine=%@ notices=%@ updateBar=%@ windowNumber=%ld fullScreen=%@ collectionBehavior=%lu titlebar=%.1f firstLineTop=%.1f findBar=%@ insets=%.1f clipY=%.1f hits=%@ TextKit2=%@",
            (text as NSString).length, String(digest.prefix(16)), selection.joined(separator: ";"),
            textView.undoManager?.undoActionName ?? "-", textView.undoManager?.groupingLevel ?? -1,
            window?.firstResponder.map { String(describing: type(of: $0)) } ?? "-",
            goToLineBar.isOpen ? "open" : "closed",
            (window?.contentView?.subviews.compactMap { ($0 as? OverlayNotice)?.text } ?? []).debugDescription,
            updateBar.map { "\(isUpdateBarSuppressed ? "suppressed" : "shown")(\($0.version))" } ?? "none", window?.windowNumber ?? 0,
            window?.styleMask.contains(.fullScreen) == true ? "yes" : "no", window?.collectionBehavior.rawValue ?? 0,
            window.map(Self.titlebarHeight(of:)) ?? -1, firstLineTopFromWindowTop() ?? -1,
            findBarRect(in: window?.contentView).map { "\(NSStringFromRect($0)) fromTop=\((window?.contentView?.bounds.maxY ?? 0) - $0.maxY)" } ?? "hidden",
            scrollView.contentInsets.top, scrollView.contentView.bounds.origin.y, debugHits(),
            textView.textLayoutManager != nil ? "yes" : "no")
    }
    #endif
}

/// Tells the editor when the find bar opens, closes or changes height, so the insets can follow it.
final class EditorScrollView: NSScrollView {
    var onFindBarChange: (() -> Void)?

    override var isFindBarVisible: Bool {
        didSet { if isFindBarVisible != oldValue { onFindBarChange?() } }
    }

    override func findBarViewDidChangeHeight() {
        super.findBarViewDidChangeHeight()
        onFindBarChange?()
    }
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

import AppKit

/// The window's content: the space-tinted backdrop, the sidebar (full,
/// compact rail or hidden), the page card, and what floats above them.
@MainActor
final class RootView: NSView {
    private let store: BrowserStore
    private let backdrop = BackdropView()
    private let sidebar: SidebarView
    private lazy var rail = SidebarRail(store: store)
    private let handle = SidebarResizeHandle()
    private let card: PageCardView
    private let emptyHint: EmptySpaceHintView
    private let dropPreview = DropPreviewView()
    private let peek = PeekContainerView()
    private let toast: ToastView
    private var commandBar: CommandBarView?
    private var sheets = SheetPresenter()
    private var shownLayout: SidebarLayout

    init(store: BrowserStore) {
        self.store = store
        sidebar = SidebarView(store: store)
        card = PageCardView(container: store.webContainer)
        emptyHint = EmptySpaceHintView(store: store)
        toast = ToastView(store: store)
        shownLayout = store.layout
        super.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        wantsLayer = true
        addSubview(backdrop)
        addSubview(card)
        card.addSubview(emptyHint)
        card.addSubview(dropPreview)
        emptyHint.autoresizingMask = [.width, .height]
        dropPreview.autoresizingMask = [.width, .height]
        dropPreview.isHidden = true
        addSubview(handle)
        addSubview(peek)
        peek.isHidden = true
        addSubview(toast)
        toast.isHidden = true
        if store.layout == .full {
            addSubview(sidebar, positioned: .above, relativeTo: card)
        } else if store.layout == .compact {
            addSubview(rail, positioned: .above, relativeTo: card)
        }
        handle.onResize = { [weak self] in self?.needsLayout = true }

        store.observe(self) { [weak self] change in self?.handle(change) }
        // The color follows the pages frame by frame.
        store.pager.observe(self) { [weak self] in self?.updateBackdrop(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        updateEmptyHint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: - Changes

    private func handle(_ change: StoreChange) {
        switch change {
        case .snapshot:
            updateBackdrop(store.snapshotAnimation)
            updateEmptyHint()
        case .pageColors:
            updateBackdrop(Motion.quick)
        case .layout:
            transitionLayout()
        case .peek:
            updatePeek()
        case .commandBar:
            updateCommandBar()
            updateEmptyHint()
        case .toast:
            updateToast()
        case .dragOverPage:
            updateDropPreview()
        case .chrome:
            needsLayout = true
        case .spaceEditor:
            if let window { sheets.showSpaceEditor(store.spaceEditor, store: store, in: window) }
        case .importSheet:
            if let window { sheets.showImport(store.importSheet, store: store, in: window) }
        default:
            break
        }
    }

    @objc private func defaultsChanged() {
        // The tint style or page matching may have changed.
        updateBackdrop(Motion.quick)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            center.addObserver(self, selector: #selector(windowStateChanged), name: name, object: window)
        }
        updateBackdrop(nil)
    }

    @objc private func windowStateChanged() {
        // Inactive windows wash their color out, as system materials do.
        updateBackdrop(Motion.quick)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackdrop(nil)
    }

    private func updateBackdrop(_ curve: Motion.Curve?) {
        let dark = effectiveAppearance.isDark
        let colors = store.tintColors(matchPage: UserDefaults.standard.bool(forKey: TintStyle.matchPageKey), dark: dark)
        let active = window.map { $0.isKeyWindow || $0.isMainWindow } ?? true
        let stops = Theme.gradient(for: Theme.blend(colors, at: store.pager.position), dark: dark, active: active,
                                   style: TintStyle.saved).map(\.cgColor)
        backdrop.setColors(stops, curve: curve)
        peek.backdrop.setColors(stops, curve: curve)
    }

    private func updateEmptyHint() {
        emptyHint.isHidden = !(store.visibleTabID == nil && store.commandBar == nil)
        if !emptyHint.isHidden { emptyHint.update() }
    }

    // MARK: - Layout

    private var chrome: Bool { !store.contentFullscreen }
    private var sidebarWidth: CGFloat { handle.width }
    /// Space between the page and the window edge. Focus mode keeps only a
    /// thin frame to drag the window by.
    private var inset: CGFloat { store.layout == .focus ? 5 : 8 }

    private func cardFrame(for layout: SidebarLayout) -> NSRect {
        guard chrome else { return bounds }
        let inset: CGFloat = layout == .focus ? 5 : 8
        let leading: CGFloat = switch layout {
        case .full: sidebarWidth + 8
        case .compact: SidebarRail.width
        case .focus: inset
        }
        return NSRect(x: leading, y: inset, width: max(bounds.width - leading - inset, 0),
                      height: max(bounds.height - inset * 2, 0))
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        card.frame = currentCardFrame
        card.isCard = chrome
        card.cornerRadius = max(store.windowRadius - inset, 6)
        emptyHint.frame = card.bounds
        dropPreview.frame = card.bounds
        // Out of sight, the sidebar and rail stay attached but hidden:
        // attaching the sidebar again costs a couple of frames as it slides in.
        if sidebar.superview === self {
            let shown = sidebarShown
            sidebar.frame = NSRect(x: -sidebarWidth * (1 - shown), y: 0, width: sidebarWidth, height: bounds.height)
            sidebar.alphaValue = shown
            sidebar.isHidden = !chrome || shown == 0
        }
        if rail.superview === self {
            let shown = railShown
            rail.frame = NSRect(x: -SidebarRail.width * (1 - shown), y: 0, width: SidebarRail.width, height: bounds.height)
            rail.alphaValue = shown
            rail.isHidden = !chrome || shown == 0
        }
        handle.isHidden = !(chrome && shownLayout == .full)
        handle.frame = NSRect(x: sidebarWidth, y: 0, width: 8, height: bounds.height)
        if !peek.isHidden { peek.frame = peekFrame(shown: true) }
        if peek.isHidden == false || sidebar.superview === peek {
            sidebar.frame = peek.bounds
        }
        layoutToast()
        commandBar?.frame = bounds
    }

    // MARK: - Layout transitions

    /// How far the sidebar and the rail are in (1) or out (0), as springs:
    /// stepped frame by frame from wherever they are, so a quick second ⌘S
    /// turns a change around smoothly, and a layout pass mid-way (a window
    /// resize) can't snap anything into place early.
    private lazy var sidebarSpring = Spring(store.layout == .full ? 1 : 0)
    private lazy var railSpring = Spring(store.layout == .compact ? 1 : 0)
    private lazy var layoutTicker = FrameTicker("layout") { [weak self] time in self?.stepLayout(at: time) }
    private var lastLayoutStep: CFTimeInterval?

    private var sidebarShown: CGFloat { sidebarSpring.value }
    private var railShown: CGFloat { railSpring.value }

    /// The card between the layouts, from how far the panels are in.
    private var currentCardFrame: NSRect {
        guard chrome else { return bounds }
        let sidebar = sidebarSpring.value, rail = railSpring.value
        let panels = min(sidebar + rail, 1)
        let inset = 5 + 3 * panels
        let leading = sidebar * (sidebarWidth + 8) + rail * SidebarRail.width + (1 - panels) * 5
        return NSRect(x: leading, y: inset, width: max(bounds.width - leading - inset, 0),
                      height: max(bounds.height - inset * 2, 0))
    }

    /// Switches layouts: the sidebar or rail slides while the page's card
    /// follows its edge. The page itself lays out once, not on every frame.
    private func transitionLayout() {
        let new = store.layout
        guard new != shownLayout else { return }
        shownLayout = new
        if new == .full, sidebar.superview !== self {
            // From the peek card, if it was there.
            sidebar.removeFromSuperview()
            addSubview(sidebar, positioned: .above, relativeTo: card)
        }
        if new == .compact, rail.superview !== self { addSubview(rail, positioned: .above, relativeTo: card) }
        sidebarSpring.target = new == .full ? 1 : 0
        railSpring.target = new == .compact ? 1 : 0
        guard chrome, !Motion.reduced, window != nil else {
            sidebarSpring.settle()
            railSpring.settle()
            finishLayoutMove()
            return
        }
        card.beginResizing(toward: cardFrame(for: new))
        if !layoutTicker.isRunning { lastLayoutStep = nil }
        layoutTicker.start(on: self)
        needsLayout = true
    }

    private func stepLayout(at time: CFTimeInterval) {
        let dt = lastLayoutStep.map { time - $0 } ?? 1.0 / 120
        lastLayoutStep = time
        sidebarSpring.step(dt)
        railSpring.step(dt)
        if sidebarSpring.isSettled, railSpring.isSettled {
            finishLayoutMove()
        } else {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    private func finishLayoutMove() {
        layoutTicker.stop()
        needsLayout = true
        layoutSubtreeIfNeeded()
        card.endResizing()
    }

    // MARK: - Peek

    private func peekFrame(shown: Bool) -> NSRect {
        let width = sidebarWidth
        return NSRect(x: shown ? 6 : -width - 12, y: 6, width: width, height: max(bounds.height - 12, 0))
    }

    /// With the sidebar hidden, it slides in over the page as a floating card.
    private func updatePeek() {
        if store.sidebarPeek {
            peek.cornerRadius = max(store.windowRadius - 6, 8)
            if sidebar.superview !== peek {
                sidebar.removeFromSuperview()
                peek.addSubview(sidebar)
                sidebar.alphaValue = 1
                sidebar.isHidden = false
            }
            peek.frame = peekFrame(shown: false)
            sidebar.frame = peek.bounds
            sidebar.autoresizingMask = [.height]
            peek.isHidden = false
            addSubview(peek, positioned: .above, relativeTo: nil)
            if let commandBar { addSubview(commandBar, positioned: .above, relativeTo: nil) }
            // Slides rather than resizes, so the sidebar's layout never reflows.
            Motion.animate(Motion.foldOut) { peek.animator().frame = peekFrame(shown: true) }
        } else if !peek.isHidden {
            Motion.animate(Motion.foldIn) { peek.animator().frame = peekFrame(shown: false) } completion: { [weak self] in
                guard let self, !store.sidebarPeek else { return }
                peek.isHidden = true
                if sidebar.superview === peek {
                    sidebar.removeFromSuperview()
                    sidebar.autoresizingMask = []
                    // Back in the window, hidden unless the layout shows it.
                    addSubview(sidebar, positioned: .above, relativeTo: card)
                }
                needsLayout = true
            }
        }
    }

    // MARK: - Overlays

    private func updateCommandBar() {
        if let mode = store.commandBar {
            guard commandBar == nil else { return }
            let bar = CommandBarView(store: store, mode: mode)
            bar.frame = bounds
            addSubview(bar, positioned: .above, relativeTo: nil)
            commandBar = bar
            bar.present()
        } else if let bar = commandBar {
            commandBar = nil
            bar.removeFromSuperview()
        }
    }

    /// Centered under the page, near the bottom of the window.
    private func layoutToast() {
        let width = toast.preferredWidth
        let pageMid = chrome ? card.frame.midX : bounds.midX
        toast.frame = NSRect(x: pageMid - width / 2, y: bounds.height - 22 - 36, width: width, height: 36)
    }

    private func updateToast() {
        if let current = store.toast {
            toast.configure(current)
            // Above everything but the command bar.
            if let commandBar {
                addSubview(toast, positioned: .below, relativeTo: commandBar)
            } else {
                addSubview(toast, positioned: .above, relativeTo: nil)
            }
            layoutToast()
            let final = toast.frame
            if toast.isHidden {
                toast.frame = final.offsetBy(dx: 0, dy: 16)
                toast.alphaValue = 0
                toast.isHidden = false
            }
            Motion.animate(Motion.settle) {
                toast.animator().frame = final
                toast.animator().alphaValue = 1
            }
        } else if !toast.isHidden {
            Motion.animate(Motion.quick) {
                toast.animator().alphaValue = 0
                toast.animator().frame.origin.y += 10
            } completion: { [weak self] in
                guard let self, store.toast == nil else { return }
                toast.isHidden = true
            }
        }
    }

    private func updateDropPreview() {
        if let id = store.dragOverPage, let tab = store.core.tab(id: id) {
            dropPreview.configure(tab)
            dropPreview.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            dropPreview.fade(visible: true, curve: Motion.settle)
        } else {
            dropPreview.fade(visible: false)
        }
    }

    // The frame around the page (and empty sidebar space) drags the window.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// The window's background: a vertical wash of the space's color.
final class BackdropView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Changes color, along `curve` or at once (while the fingers swipe).
    func setColors(_ colors: [CGColor], curve: Motion.Curve?) {
        CATransaction.begin()
        if let curve, !Motion.reduced {
            CATransaction.setAnimationDuration(curve.duration)
            CATransaction.setAnimationTimingFunction(curve.timing)
        } else {
            CATransaction.setDisableActions(true)
        }
        gradient.colors = colors
        CATransaction.commit()
    }
}

/// The floating card the hidden sidebar slides out in.
final class PeekContainerView: FlippedView {
    let backdrop = BackdropView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(backdrop)
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        backdrop.wantsLayer = true
        backdrop.layer?.masksToBounds = true
        backdrop.layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    var cornerRadius: CGFloat = 10 {
        didSet { backdrop.layer?.cornerRadius = cornerRadius; needsDisplay = true }
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
    }

    override func updateLayer() {
        guard let layer, let back = backdrop.layer else { return }
        back.borderWidth = 0.5
        back.borderColor = Theme.faint(0.1).cgColor
        layer.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 4, height: 0)
    }
}

/// Drag to resize the sidebar. Past its limits it stretches a little, then
/// springs back.
final class SidebarResizeHandle: NSView {
    static let range: ClosedRange<CGFloat> = 200...420
    var onResize: (() -> Void)?
    private var startWidth: CGFloat?
    private var startX: CGFloat = 0

    private(set) var width: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
        return saved > 0 ? saved : 260
    }()

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startWidth = width
        startX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startWidth else { return }
        width = Self.rubberBand(startWidth + event.locationInWindow.x - startX)
        onResize?()
    }

    override func mouseUp(with event: NSEvent) {
        startWidth = nil
        let clamped = min(max(width, Self.range.lowerBound), Self.range.upperBound)
        if clamped != width {
            width = clamped
            Motion.animate(Motion.settle) { superview?.layoutSubtreeIfNeeded(); onResize?(); superview?.layoutSubtreeIfNeeded() }
        }
        UserDefaults.standard.set(Double(width), forKey: "sidebarWidth")
    }

    private static func rubberBand(_ raw: CGFloat) -> CGFloat {
        if raw < range.lowerBound { return range.lowerBound - (range.lowerBound - raw) / 4 }
        if raw > range.upperBound { return range.upperBound + (raw - range.upperBound) / 4 }
        return raw
    }
}

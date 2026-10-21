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
    private let smear = MotionSmearView()
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
        // The peek card sits right under the sidebar, which never leaves this
        // view: moving it into the peek redrew it all as it slid in.
        addSubview(smear)
        addSubview(peek)
        peek.isHidden = true
        addSubview(sidebar)
        addSubview(handle)
        addSubview(toast)
        toast.isHidden = true
        if store.layout == .compact { addSubview(rail, positioned: .above, relativeTo: card) }
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
        smear.colors = stops
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
        // The sidebar is either part of the layout, sliding in and out with
        // it, or floating on the peek card; hidden, it waits at the peek's
        // size so the peek doesn't make it lay out again.
        let shown = sidebarShown, peeking = peekSpring.value
        // Out of sight it waits just past the left edge rather than hidden:
        // a hidden list makes no rows, and making them all as it slides in
        // cost several frames.
        if shownLayout == .full || shown > 0.001 {
            sidebar.frame = NSRect(x: -sidebarWidth * (1 - shown), y: 0, width: sidebarWidth, height: bounds.height)
            sidebar.alphaValue = shown
        } else {
            sidebar.frame = peekFrame(at: peeking)
            sidebar.alphaValue = 1
        }
        sidebar.isHidden = !chrome
        peek.isHidden = !chrome || peeking == 0 || shownLayout == .full
        if !peek.isHidden { peek.frame = peekFrame(at: peeking) }
        if rail.superview === self {
            let shown = railShown
            rail.frame = NSRect(x: -SidebarRail.width * (1 - shown), y: 0, width: SidebarRail.width, height: bounds.height)
            rail.alphaValue = shown
            rail.isHidden = !chrome || shown == 0
        }
        handle.isHidden = !(chrome && shownLayout == .full)
        handle.frame = NSRect(x: sidebarWidth, y: 0, width: 8, height: bounds.height)
        if !peek.isHidden {
            smear.update(edge: peek.frame, cornerRadius: peek.cornerRadius,
                         speed: peekSpring.velocity * (sidebarWidth + 18))
        } else {
            smear.update(edge: .zero, cornerRadius: 0, speed: 0)
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

    /// How far the floating sidebar is in while it peeks over the page.
    private lazy var peekSpring = Spring(0, response: Motion.peekResponse)
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
    /// follows its edge, the page reflowing with it frame by frame as in Arc.
    /// (Laying it out only once left a visible jump to the new layout as the
    /// slide ended; the engine lays a page out as fast as it can keep up, so
    /// the slide itself stays smooth.)
    private func transitionLayout() {
        let new = store.layout
        guard new != shownLayout else { return }
        shownLayout = new
        if new == .compact, rail.superview !== self { addSubview(rail, positioned: .above, relativeTo: card) }
        sidebarSpring.target = new == .full ? 1 : 0
        railSpring.target = new == .compact ? 1 : 0
        // Pinned while it peeks (⌘S with the sidebar out): it carries on
        // from where the peek has it instead of sliding in from the edge.
        if new == .full, peekSpring.value > sidebarSpring.value {
            sidebarSpring.value = peekSpring.value
            sidebarSpring.velocity = peekSpring.velocity
        }
        if new == .full { peekSpring.settle() }
        guard chrome, !Motion.reduced, window != nil else {
            sidebarSpring.settle()
            railSpring.settle()
            finishLayoutMove()
            return
        }
        if !layoutTicker.isRunning { lastLayoutStep = nil }
        layoutTicker.start(on: self)
        needsLayout = true
    }

    private func stepLayout(at time: CFTimeInterval) {
        let dt = lastLayoutStep.map { time - $0 } ?? 1.0 / 120
        lastLayoutStep = time
        sidebarSpring.step(dt)
        railSpring.step(dt)
        peekSpring.step(dt)
        if sidebarSpring.isSettled, railSpring.isSettled, peekSpring.isSettled {
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
    }

    // MARK: - Peek

    /// The floating sidebar `p` of the way in (0: just past the left edge).
    private func peekFrame(at p: CGFloat) -> NSRect {
        let width = sidebarWidth
        let hidden = -width - 12, shown: CGFloat = 6
        return NSRect(x: hidden + (shown - hidden) * p, y: 6, width: width, height: max(bounds.height - 12, 0))
    }

    /// With the sidebar hidden, it slides in over the page as a floating
    /// card, by a spring: a quick move away turns it around smoothly.
    private func updatePeek() {
        peek.cornerRadius = max(store.windowRadius - 6, 8)
        peekSpring.target = store.sidebarPeek ? 1 : 0
        guard chrome, !Motion.reduced, window != nil else {
            peekSpring.settle()
            needsLayout = true
            return
        }
        if !layoutTicker.isRunning { lastLayoutStep = nil }
        layoutTicker.start(on: self)
        needsLayout = true
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
        // From a path: worked out from the sidebar's pixels, the shadow cost
        // a full redraw on every frame of the slide.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        CATransaction.commit()
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

/// A soft smear off the right edge of the sidebar as it peeks in or out,
/// as long as the sidebar is fast and gone as it settles: it reads as
/// motion blur on the edge sweeping over the page. Plain gradients, so it
/// costs nothing per frame (blurring the sidebar itself with a filter cost
/// about one frame in thirty).
final class MotionSmearView: NSView {
    private let fill = CAGradientLayer()
    private let fade = CAGradientLayer()

    /// The sidebar's colors, top to bottom.
    var colors: [CGColor] = [] {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.colors = colors
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        fill.startPoint = CGPoint(x: 0.5, y: 1)
        fill.endPoint = CGPoint(x: 0.5, y: 0)
        // Solid at the edge, gone at the far end, easing out.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [1, 0.55, 0.2, 0].map { NSColor.black.withAlphaComponent($0).cgColor }
        fade.locations = [0, 0.3, 0.65, 1]
        fill.mask = fade
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `edge` is the sidebar's frame, `speed` in points per second.
    func update(edge: NSRect, cornerRadius: CGFloat, speed: CGFloat) {
        // A slowed-down capture shows it as at full speed.
        let length = min(abs(speed) * CGFloat(Motion.slow) / 55, 72)
        guard length >= 2, !Motion.reduced else {
            isHidden = true
            return
        }
        isHidden = false
        // Tucked a little under the edge so there is no seam, and clear of
        // the rounded corners.
        frame = NSRect(x: edge.maxX - 2, y: edge.minY + cornerRadius,
                       width: length + 2, height: max(edge.height - cornerRadius * 2, 0))
        alphaValue = min(length / 24, 1) * 0.9
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fade.frame = bounds
        CATransaction.commit()
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

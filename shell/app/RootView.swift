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
    private let elsewhereHint: ElsewhereHintView
    private let dropPreview = DropPreviewView()
    private let devToolbar: DevToolbarView
    private let inspector: InspectorView
    private let inspectorHandle = InspectorResizeHandle()
    private let agentGlow = AgentGlowView()
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
        elsewhereHint = ElsewhereHintView(store: store)
        devToolbar = DevToolbarView(store: store)
        inspector = InspectorView(store: store)
        toast = ToastView(store: store)
        shownLayout = store.layout
        super.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        wantsLayer = true
        addSubview(backdrop)
        addSubview(inspector)
        addSubview(inspectorHandle)
        addSubview(card)
        inspector.isHidden = !store.inspectorOpen
        inspectorHandle.onDrag = { [weak self] x in self?.resizeInspector(to: x) }
        card.addSubview(emptyHint)
        card.addSubview(elsewhereHint)
        card.addSubview(dropPreview)
        card.addSubview(devToolbar)
        card.addSubview(agentGlow)
        emptyHint.autoresizingMask = [.width, .height]
        elsewhereHint.autoresizingMask = [.width, .height]
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
        store.webContainer.onPageAreaChange = { [weak self] in self?.needsLayout = true }

        store.observe(self) { [weak self] change in self?.handle(change) }
        // The color follows the pages frame by frame.
        store.pager.observe(self) { [weak self] in self?.updateBackdrop(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        updateEmptyHint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: - Changes

    private func handle(_ change: StoreChange) {
        switch change {
        case .snapshot:
            // A space's colour edited, or the page colour of another tab
            // (with Match Page Colour) washes in; on a space switch the
            // pager moves the colour with the pages.
            let sameSpace = store.snapshot.activeSpace == backdropSpace
            backdropSpace = store.snapshot.activeSpace
            updateBackdrop(store.snapshotAnimation ?? (sameSpace ? Motion.quick : nil))
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
        case .elsewhere:
            elsewhereHint.update()
            updateEmptyHint()
        case .toast:
            updateToast()
        case .agent:
            agentGlow.setActive(store.agentActingOnVisibleTab)
        case .dragOverPage:
            updateDropPreview()
        case .inspector:
            transitionInspector()
        case .chrome:
            // Into and out of page full screen (a video), the card grows to
            // the window's edges and back.
            Motion.animate(Motion.settle) {
                needsLayout = true
                layoutSubtreeIfNeeded()
            }
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
        // Docked DevTools taking the keyboard doesn't make the window inactive.
        let active = window.map { $0.isKeyWindow || $0.isMainWindow || NSApp.keyWindow?.parent === $0 } ?? true
        let tint = Theme.gradient(for: Theme.blend(colors, at: store.pager.position), dark: dark, active: active,
                                  style: TintStyle.saved)
        inspector.setTint(tint, curve: curve)
        let stops = tint.map(\.cgColor)
        backdrop.setColors(stops, curve: curve)
        peek.backdrop.setColors(stops, curve: curve)
        smear.colors = stops
    }

    private var backdropSpace: UInt64?

    private func updateEmptyHint() {
        let visible = store.visibleTabID == nil && store.commandBar == nil
        if visible { emptyHint.update() }
        emptyHint.setVisible(visible, animated: true, curve: Motion.fade)
        elsewhereHint.setVisible(store.visibleTabElsewhere && store.commandBar == nil, animated: true, curve: Motion.fade)
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
        // The corners follow the frame's inset as the layout changes.
        let panels = min(sidebarSpring.value + railSpring.value, 1)
        card.cornerRadius = max(store.windowRadius - (5 + 3 * panels), 6)
        emptyHint.frame = card.bounds
        elsewhereHint.frame = card.bounds
        dropPreview.frame = card.bounds
        // The card isn't flipped: the strip runs along its top.
        // Over the page only, not docked DevTools beside it.
        let page = store.webContainer.pageArea
        agentGlow.frame = card.bounds
        agentGlow.cornerRadius = card.isCard ? card.cornerRadius : 0
        devToolbar.frame = NSRect(x: 0, y: card.bounds.height - DevToolbarView.height,
                                  width: page.width > 0 ? page.width : card.bounds.width, height: DevToolbarView.height)
        layoutInspector()
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
        // The traffic lights ride on the peek card, in line with its toolbar.
        // They never leave the window's corner to come in with it: in Compact
        // they stay visible, and sliding out and back would be a jump.
        store.offsetTrafficLights(peek.isHidden ? .zero
            : CGSize(width: max(peek.frame.minX, 0), height: peek.frame.minY * min(max(peeking, 0), 1)))
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
    /// How far the inspector is in on the right.
    private lazy var inspectorSpring = Spring(store.inspectorOpen ? 1 : 0)
    private var sidebarShown: CGFloat { sidebarSpring.value }
    private var railShown: CGFloat { railSpring.value }

    /// The card between the layouts, from how far the panels are in.
    private var currentCardFrame: NSRect {
        guard chrome else { return bounds }
        let sidebar = sidebarSpring.value, rail = railSpring.value
        let panels = min(sidebar + rail, 1)
        let inset = 5 + 3 * panels
        let leading = sidebar * (sidebarWidth + 8) + rail * SidebarRail.width + (1 - panels) * 5
        let trailing = inspectorSpring.value * (inspectorWidth + 8)
        return NSRect(x: leading, y: inset, width: max(bounds.width - leading - inset - trailing, 0),
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
        inspectorSpring.step(dt)
        if sidebarSpring.isSettled, railSpring.isSettled, peekSpring.isSettled, inspectorSpring.isSettled {
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

    // MARK: - Inspector

    /// The inspector's width, leaving the page at least a phone's.
    private var inspectorWidth: CGFloat {
        min(InspectorSettings.width, max(bounds.width - 420, InspectorSettings.minWidth))
    }

    /// The inspector rides in from the right edge as the page makes room.
    private func layoutInspector() {
        let shown = inspectorSpring.value
        let width = inspectorWidth
        let visible = chrome && shown > 0.001
        inspector.isHidden = !visible
        inspectorHandle.isHidden = !visible || shown < 1
        guard visible else { return }
        let inset: CGFloat = 8
        let x = bounds.width - inset - shown * width + (1 - shown) * inset
        inspector.frame = NSRect(x: x.rounded(), y: 0, width: width, height: bounds.height)
        inspector.alphaValue = min(shown * 1.5, 1)
        inspector.cornerRadius = card.cornerRadius
        inspectorHandle.frame = NSRect(x: card.frame.maxX, y: 0, width: 8, height: bounds.height)
    }

    private func transitionInspector() {
        inspectorSpring.target = store.inspectorOpen ? 1 : 0
        if store.inspectorOpen { inspector.update() }
        guard chrome, !Motion.reduced, window != nil else {
            inspectorSpring.settle()
            finishLayoutMove()
            return
        }
        if !layoutTicker.isRunning { lastLayoutStep = nil }
        layoutTicker.start(on: self)
        needsLayout = true
    }

    private func resizeInspector(to x: CGFloat) {
        let width = bounds.width - 8 - x - 8
        UserDefaults.standard.set(Double(max(width, InspectorSettings.minWidth)), forKey: InspectorSettings.widthKey)
        needsLayout = true
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
            bar.dismiss { bar.removeFromSuperview() }
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
            let shown = toast.frame
            layoutToast()
            let final = toast.frame
            if toast.isHidden {
                toast.frame = final.offsetBy(dx: 0, dy: 16)
                toast.alphaValue = 0
                toast.isHidden = false
            } else {
                // Replacing a toast: it resizes to the new message.
                toast.frame = shown
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
            let appearing = dropPreview.isHidden
            dropPreview.configure(tab)
            dropPreview.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            dropPreview.fade(visible: true, curve: Motion.settle)
            // The little-window preview grows into place as it appears.
            if appearing, !Motion.reduced, let layer = dropPreview.layer {
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.96
                grow.toValue = 1
                grow.duration = Motion.settle.duration
                grow.timingFunction = Motion.settle.timing
                layer.add(grow, forKey: "grow")
            }
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

    @available(*, unavailable)
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

/// An edge of light around the page while an agent acts on it, so it's
/// always clear when something other than the person is driving.
final class AgentGlowView: NSView {
    private let ring = CALayer()
    var cornerRadius: CGFloat = 8 {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        ring.borderWidth = 2
        ring.cornerCurve = .continuous
        ring.shadowRadius = 12
        ring.shadowOffset = .zero
        ring.shadowOpacity = 1
        ring.opacity = 0
        layer?.addSublayer(ring)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.cornerRadius = cornerRadius
        CATransaction.commit()
    }

    func setActive(_ active: Bool) {
        let accent = NSColor.controlAccentColor
        ring.borderColor = accent.cgColor
        ring.shadowColor = accent.withAlphaComponent(0.8).cgColor
        if active { isHidden = false }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ring.presentation()?.opacity ?? ring.opacity
        fade.toValue = active ? 1 : 0
        fade.duration = Motion.reduced ? 0 : (active ? Motion.quick.duration : Motion.fade.duration * 2)
        ring.opacity = active ? 1 : 0
        ring.add(fade, forKey: "fade")
        // It breathes while the agent works.
        if active, !Motion.reduced, ring.animation(forKey: "breathe") == nil {
            let breathe = CABasicAnimation(keyPath: "shadowRadius")
            breathe.fromValue = 6
            breathe.toValue = 16
            breathe.duration = 0.9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            ring.add(breathe, forKey: "breathe")
        } else if !active {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade.duration) { [weak self] in
                guard let self, ring.opacity == 0 else { return }
                ring.removeAnimation(forKey: "breathe")
                isHidden = true
            }
        }
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

    @available(*, unavailable)
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

    @available(*, unavailable)
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

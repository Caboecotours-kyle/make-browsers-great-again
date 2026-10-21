import AppKit

/// Horizontal paging between spaces, driven directly by trackpad scroll
/// events so a two-finger swipe anywhere in the sidebar moves the spaces
/// with the fingers and springs to the nearest one on release.
///
/// Animated moves are stepped on every display frame rather than handed to
/// Core Animation: a view animated that way already sits at its destination,
/// and AppKit doesn't keep drawing a page it thinks is off screen, so a
/// space sliding away would go blank. Stepping also keeps the pages and the
/// window's color in step with each other, as under the fingers.
@MainActor
final class PagerModel {
    /// Fractional index of the space on screen.
    private(set) var position: CGFloat = 0
    /// Where an animated move is heading, while it runs.
    private(set) var destination: CGFloat?
    /// What an animated move covers, so the pages along the way are ready.
    private(set) var travel: ClosedRange<CGFloat>?
    /// The view whose display drives animated moves.
    weak var view: NSView?

    private struct Observer {
        weak var owner: AnyObject?
        let handle: @MainActor () -> Void
    }
    private var observers: [Observer] = []

    /// Calls `handle` whenever the position on screen changes.
    func observe(_ owner: AnyObject, _ handle: @escaping @MainActor () -> Void) {
        observers.append(Observer(owner: owner, handle: handle))
    }

    func setPosition(_ value: CGFloat, animated: Bool) {
        if animated, !Motion.reduced, view?.window != nil {
            guard value != (destination ?? position) else { return }
            move(to: value)
            return
        }
        stopMoving()
        guard value != position else { return }
        position = value
        notify()
    }

    private func notify() {
        observers.removeAll { $0.owner == nil }
        for observer in observers { observer.handle() }
    }

    // MARK: Animated moves

    private lazy var ticker = FrameTicker("space switch") { [weak self] time in self?.step(at: time) }
    /// When the move's first frame was shown. Its clock starts there, so
    /// work done as the move begins (switching the page) delays its start
    /// by a moment instead of making it skip mid-way.
    private var moveStart: CFTimeInterval?
    private var moveFrom: CGFloat = 0

    private func move(to value: CGFloat) {
        moveFrom = position
        moveStart = nil
        destination = value
        travel = min(position, value)...max(position, value)
        if let view { ticker.start(on: view) }
    }

    private func step(at time: CFTimeInterval) {
        guard let destination else { return }
        let start = moveStart ?? time - 1.0 / 120
        moveStart = start
        let t = min(max((time - start) / Motion.glide.duration, 0), 1)
        position = t >= 1 ? destination : moveFrom + (destination - moveFrom) * CGFloat(Motion.glide.progress(at: t))
        if t >= 1 { stopMoving() }
        notify()
    }

    private func stopMoving() {
        ticker.stop()
        destination = nil
        travel = nil
    }

    var pageCount = 1
    var pageWidth: CGFloat = 260
    /// Sidebar frame in the hosting view's (top-left origin) coordinates.
    var sidebarFrame: CGRect = .zero
    /// Called with the space index a swipe settled on.
    var onSettle: ((Int) -> Void)?
    /// Called with the space a swipe heads for as it starts.
    var onSwipeTowards: ((Int) -> Void)?

    private enum Tracking {
        case idle
        case undecided(dx: CGFloat, dy: CGFloat)
        case horizontal(start: CGFloat, dx: CGFloat, velocity: CGFloat)
        case vertical
        /// Swallows the momentum events that follow a horizontal swipe.
        case momentum
    }

    private var tracking = Tracking.idle

    var isTracking: Bool {
        switch tracking {
        case .horizontal, .momentum: true
        default: false
        }
    }

    /// Moves to `index` unless the user is swiping.
    func show(_ index: Int, animated: Bool) {
        guard !isTracking, (destination ?? position) != CGFloat(index) else { return }
        setPosition(CGFloat(index), animated: animated)
    }

    private var lastWheelStep: TimeInterval = 0

    private func inSidebar(_ event: NSEvent, _ host: NSView) -> Bool {
        var point = host.convert(event.locationInWindow, from: nil)
        if !host.isFlipped { point.y = host.bounds.height - point.y }
        return sidebarFrame.contains(point)
    }

    /// Returns true if the event was consumed.
    func handle(_ event: NSEvent, in host: NSView) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return handleWheel(event, in: host) }

        if event.phase.contains(.began) {
            tracking = inSidebar(event, host) && pageCount > 1 ? .undecided(dx: 0, dy: 0) : .idle
        }
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)

        switch tracking {
        case .idle, .vertical:
            if ended { tracking = .idle }
            return false

        case .undecided(var dx, var dy):
            dx += event.scrollingDeltaX
            dy += event.scrollingDeltaY
            if abs(dx) > 6, abs(dx) > abs(dy) * 1.2 {
                // The fingers take over from a move still running.
                stopMoving()
                onSwipeTowards?(Int(position.rounded()) + (dx < 0 ? 1 : -1))
                tracking = .horizontal(start: position, dx: dx, velocity: event.scrollingDeltaX)
                setPosition(rubberBand(position - dx / pageWidth), animated: false)
                return true
            }
            tracking = ended ? .idle : abs(dy) > 6 ? .vertical : .undecided(dx: dx, dy: dy)
            return false

        case .horizontal(let start, var dx, let velocity):
            dx += event.scrollingDeltaX
            if ended {
                // The ended event carries no movement; use the last real delta.
                settle(from: start - dx / pageWidth, velocity: velocity)
                tracking = .momentum
            } else {
                tracking = .horizontal(start: start, dx: dx, velocity: event.scrollingDeltaX)
                setPosition(rubberBand(start - dx / pageWidth), animated: false)
            }
            return true

        case .momentum:
            if event.momentumPhase.isEmpty && event.phase.isEmpty {
                tracking = .idle
                return false
            }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                tracking = .idle
            }
            return true
        }
    }

    /// A mouse's horizontal wheel (or Shift-scroll) over the sidebar steps
    /// one space at a time.
    private func handleWheel(_ event: NSEvent, in host: NSView) -> Bool {
        var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        // The system usually turns Shift-scroll horizontal; not always.
        if event.modifierFlags.contains(.shift), dx == 0 { (dx, dy) = (dy, 0) }
        guard pageCount > 1, abs(dx) >= 1, abs(dx) > abs(dy), inSidebar(event, host) else { return false }
        // One step per flick of the wheel, however many notches it reports.
        guard event.timestamp - lastWheelStep > 0.35 else { return true }
        lastWheelStep = event.timestamp
        let current = Int((destination ?? position).rounded())
        let target = min(max(current + (dx < 0 ? 1 : -1), 0), pageCount - 1)
        guard target != current else { return true }
        setPosition(CGFloat(target), animated: true)
        onSettle?(target)
        return true
    }

    private func rubberBand(_ raw: CGFloat) -> CGFloat {
        let last = CGFloat(pageCount - 1)
        if raw < 0 { return raw / 3 }
        if raw > last { return last + (raw - last) / 3 }
        return raw
    }

    private func settle(from raw: CGFloat, velocity: CGFloat) {
        var target = raw.rounded()
        // A flick moves one space even if the fingers travelled less than half.
        if abs(velocity) > 6 {
            target = velocity > 0 ? raw.rounded(.down) : raw.rounded(.up)
        }
        let index = Int(min(max(target, 0), CGFloat(pageCount - 1)))
        setPosition(CGFloat(index), animated: true)
        onSettle?(index)
    }
}

/// Holds the engine views of loaded tabs and shows the visible one. Hidden
/// views are throttled by the engine automatically.
final class WebContainerView: NSView {
    private weak var current: MBWebView?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set {
            layer?.cornerRadius = newValue
            layer?.cornerCurve = .continuous
        }
    }

    /// A one-pixel edge drawn above the page, or none.
    func setBorder(_ color: NSColor?) {
        layer?.borderWidth = color == nil ? 0 : 1 / (window?.backingScaleFactor ?? 2)
        layer?.borderColor = color?.cgColor
    }

    func add(_ view: MBWebView) {
        view.isHidden = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    /// Shows `view`, hiding the one shown before. With `crossfade` (a space
    /// switch) the old page fades out over the new one instead.
    func show(_ view: MBWebView?, crossfade: Bool = false) {
        guard view !== current else { return }
        // A view moved to a little window is no longer this container's.
        let previous = current?.superview === self ? current : nil
        let view = view?.superview === self ? view : nil
        if let view {
            // It may still be fading out from an earlier switch.
            view.layer?.removeAnimation(forKey: "opacity")
            view.alphaValue = 1
            view.layer?.zPosition = 0
            view.frame = bounds
            view.isHidden = false
        }
        current = view
        guard let previous else { return }
        guard crossfade, view != nil, !Motion.reduced else {
            previous.isHidden = true
            return
        }
        previous.layer?.zPosition = 1
        Motion.animate(Motion.fade) {
            previous.animator().alphaValue = 0
        } completion: { [weak self, weak previous] in
            guard let previous else { return }
            previous.layer?.zPosition = 0
            previous.alphaValue = 1
            if previous !== self?.current { previous.isHidden = true }
        }
    }
}

/// The page as a card: a soft shadow and a hairline around the shared
/// WebContainerView, with corners that follow the window's.
final class PageCardView: NSView {
    let container: WebContainerView
    private let shadowLayer = CALayer()

    init(container: WebContainerView) {
        self.container = container
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        shadowLayer.backgroundColor = NSColor.white.cgColor
        shadowLayer.cornerCurve = .continuous
        shadowLayer.shadowRadius = 6
        shadowLayer.shadowOffset = CGSize(width: 0, height: -1)
        shadowLayer.shadowOpacity = 1
        layer?.addSublayer(shadowLayer)
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        addSubview(container)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    /// Card corners and edge, or none for full screen.
    // Set on every layout pass, so only a real change redraws.
    var isCard = true {
        didSet { if isCard != oldValue { needsDisplay = true; needsLayout = true } }
    }
    var cornerRadius: CGFloat = 8 {
        didSet { if cornerRadius != oldValue { needsDisplay = true; needsLayout = true } }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.cornerRadius = isCard ? cornerRadius : 0
        // A shadow without a path is worked out from the layer's pixels
        // again whenever the card changes size: every frame of ⌘S.
        shadowLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: shadowLayer.cornerRadius,
                                        cornerHeight: shadowLayer.cornerRadius, transform: nil)
        shadowLayer.isHidden = !isCard
        CATransaction.commit()
        container.cornerRadius = isCard ? cornerRadius : 0
    }

    override func updateLayer() {
        let dark = effectiveAppearance.isDark
        shadowLayer.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.3 : 0.07).cgColor
        container.setBorder(isCard ? (dark ? .white.withAlphaComponent(0.1) : .black.withAlphaComponent(0.08)) : nil)
    }
}

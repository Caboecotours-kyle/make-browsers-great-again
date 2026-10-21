import AppKit

/// Horizontal paging between spaces, driven directly by trackpad scroll
/// events so a two-finger swipe anywhere in the sidebar moves the spaces
/// with the fingers and springs to the nearest one on release.
@MainActor
final class PagerModel {
    /// Fractional index of the space on screen.
    private(set) var position: CGFloat = 0

    private struct Observer {
        weak var owner: AnyObject?
        let handle: @MainActor (_ animated: Bool) -> Void
    }
    private var observers: [Observer] = []

    /// Calls `handle` whenever the position changes, with whether to
    /// animate to it (a settle) or follow it directly (fingers moving).
    func observe(_ owner: AnyObject, _ handle: @escaping @MainActor (_ animated: Bool) -> Void) {
        observers.append(Observer(owner: owner, handle: handle))
    }

    func setPosition(_ value: CGFloat, animated: Bool) {
        guard value != position else { return }
        position = value
        observers.removeAll { $0.owner == nil }
        for observer in observers { observer.handle(animated) }
    }

    var pageCount = 1
    var pageWidth: CGFloat = 260
    /// Sidebar frame in the hosting view's (top-left origin) coordinates.
    var sidebarFrame: CGRect = .zero
    /// Called with the space index a swipe settled on.
    var onSettle: ((Int) -> Void)?

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
        guard !isTracking, position != CGFloat(index) else { return }
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
        let current = Int(position.rounded())
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

    func show(_ view: MBWebView?) {
        guard view !== current else { return }
        // A view moved to a little window is no longer this container's.
        if current?.superview === self { current?.isHidden = true }
        let view = view?.superview === self ? view : nil
        view?.frame = bounds
        view?.isHidden = false
        current = view
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
    var isCard = true {
        didSet { needsDisplay = true; needsLayout = true }
    }
    var cornerRadius: CGFloat = 8 {
        didSet { needsDisplay = true; needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.cornerRadius = isCard ? cornerRadius : 0
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

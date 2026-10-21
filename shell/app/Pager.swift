import AppKit
import SwiftUI

/// Horizontal paging between spaces, driven directly by trackpad scroll
/// events so a two-finger swipe anywhere in the sidebar moves the spaces
/// with the fingers and springs to the nearest one on release.
@MainActor
final class PagerModel: ObservableObject {
    /// Fractional index of the space on screen.
    @Published var position: CGFloat = 0

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
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { position = CGFloat(index) }
        } else {
            position = CGFloat(index)
        }
    }

    /// Returns true if the event was consumed.
    func handle(_ event: NSEvent, in host: NSView) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }

        if event.phase.contains(.began) {
            var point = host.convert(event.locationInWindow, from: nil)
            if !host.isFlipped { point.y = host.bounds.height - point.y }
            tracking = sidebarFrame.contains(point) && pageCount > 1 ? .undecided(dx: 0, dy: 0) : .idle
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
                position = rubberBand(position - dx / pageWidth)
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
                position = rubberBand(start - dx / pageWidth)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { position = CGFloat(index) }
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

    func add(_ view: MBWebView) {
        view.isHidden = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    func show(_ view: MBWebView?) {
        guard view !== current else { return }
        current?.isHidden = true
        view?.frame = bounds
        view?.isHidden = false
        current = view
    }
}

/// Places the shared WebContainerView in the SwiftUI layout. The container
/// is re-parented rather than recreated so live pages survive layout changes.
struct WebArea: NSViewRepresentable {
    let container: WebContainerView
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.autoresizesSubviews = true
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if container.superview !== host {
            container.removeFromSuperview()
            container.frame = host.bounds
            container.autoresizingMask = [.width, .height]
            host.addSubview(container)
        }
        container.cornerRadius = cornerRadius
    }
}

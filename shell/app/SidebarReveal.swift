import AppKit

/// Shows the hidden sidebar and the traffic lights in Focus mode the way Arc
/// and Dia do. The sidebar slides out after the pointer rests at the
/// window's left edge for a moment, so passing by doesn't open it. It stays
/// out while the pointer is within reach (also past the window and screen
/// edge), a menu is open or a button is held, and goes away shortly after
/// the pointer leaves. Works from mouse-moved events, so it costs nothing
/// while the pointer is still.
@MainActor
final class SidebarReveal {
    private weak var store: BrowserStore?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var openTimer: Timer?
    private var closeTimer: Timer?
    private var menuOpen = false

    /// How long the pointer rests at the edge before the sidebar opens.
    private let intentDelay: TimeInterval = 0.12
    /// How long the pointer may be out of reach before the sidebar closes.
    private let graceDelay: TimeInterval = 0.3
    /// Extra reach beyond the sidebar's width that keeps it open.
    private let reach: CGFloat = 24
    /// Width of the edge that opens the sidebar.
    private let edge: CGFloat = 6

    init(store: BrowserStore) {
        self.store = store
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.pointerMoved()
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuOpen = false
                self?.pointerMoved()
            }
        })
    }

    /// The sidebar's width, which sets how far the pointer may wander.
    private var sidebarWidth: CGFloat {
        UserDefaults.standard.object(forKey: "sidebarWidth") as? CGFloat ?? 260
    }

    private enum Zone { case edge, reach, away }

    private func zone() -> Zone {
        guard let window = store?.window, window.isVisible, NSApp.isActive else { return .away }
        let frame = window.frame
        let point = NSEvent.mouseLocation
        let x = point.x - frame.minX
        let fromTop = frame.maxY - point.y
        guard fromTop >= -reach, point.y >= frame.minY - reach else { return .away }
        // Anything left of the window counts: the screen edge, or past the
        // window when it doesn't touch the edge.
        if x <= edge, fromTop >= 0, point.y >= frame.minY { return .edge }
        if x <= sidebarWidth + reach { return .reach }
        return .away
    }

    private func pointerMoved() {
        guard let store, store.layout != .full, !store.contentFullscreen else {
            cancelTimers()
            return
        }
        let zone = zone()
        if store.sidebarPeek {
            let held = NSEvent.pressedMouseButtons != 0
            if zone == .away, !menuOpen, !held {
                startOnce(&closeTimer, after: graceDelay) { [weak self] in
                    guard let self, self.zone() == .away, !self.menuOpen else { return }
                    self.store?.sidebarPeek = false
                }
            } else {
                stop(&closeTimer)
            }
            return
        }
        if zone == .edge {
            startOnce(&openTimer, after: intentDelay) { [weak self] in
                guard let self, self.zone() == .edge else { return }
                self.store?.sidebarPeek = true
            }
        } else {
            stop(&openTimer)
        }
    }

    /// Starts a one-shot timer unless one is already pending, so steady
    /// pointer movement doesn't keep postponing it.
    private func startOnce(_ timer: inout Timer?, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        guard timer?.isValid != true else { return }
        let t = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop(_ timer: inout Timer?) {
        timer?.invalidate()
        timer = nil
    }

    private func cancelTimers() {
        stop(&openTimer)
        stop(&closeTimer)
    }
}

import AppKit
import SwiftUI

/// A tab popped out of the sidebar into a small window of its own, like
/// Arc's Little Arc. The tab stays in its space; closing the window, "Open
/// in Sidebar" or selecting the tab in the sidebar puts it back.
@MainActor
final class LittleWindow: NSObject, NSWindowDelegate {
    let tabID: UInt64
    let window: NSWindow
    private weak var store: BrowserStore?
    /// Holds the tab's web view inside the window's card.
    private let host = NSView()
    private var returnToSidebar = false

    init(tabID: UInt64, view: MBWebView, store: BrowserStore, near point: NSPoint?) {
        self.tabID = tabID
        self.store = store
        let size = NSSize(width: 560, height: 700)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 320)
        window.acceptsMouseMovedEvents = true
        super.init()
        window.delegate = self

        host.wantsLayer = true
        host.layer?.masksToBounds = true
        host.layer?.cornerCurve = .continuous
        host.layer?.backgroundColor = NSColor.white.cgColor
        view.removeFromSuperview()
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        view.isHidden = false
        host.addSubview(view)

        let content = NSHostingView(rootView: LittleWindowView(tabID: tabID, host: host) { [weak self] in
            self?.putBack()
        }.environmentObject(store))
        content.sizingOptions = []
        window.contentView = content
        host.layer?.cornerRadius = max(window.systemCornerRadius - 6, 6)
        place(near: point)
    }

    func show() {
        guard !window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Grows out of where it was opened.
        let frame = window.frame
        window.setFrame(frame.insetBy(dx: frame.width * 0.06, dy: frame.height * 0.06), display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = 1
        }
    }

    /// Closes the window and selects the tab in the main window.
    func putBack() {
        returnToSidebar = true
        fadeOutAndClose()
    }

    private func fadeOutAndClose() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.window.close() }
        }
    }

    /// Closes the window when its tab goes away; the store has the view.
    func dismiss() {
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        store?.littleWindowClosed(tabID, select: returnToSidebar)
    }

    /// Centered on where the tab was dropped, kept on that screen.
    private func place(near point: NSPoint?) {
        guard let point, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let size = window.frame.size
        let area = screen.visibleFrame
        let x = min(max(point.x - size.width / 2, area.minX), area.maxX - size.width)
        let y = min(max(point.y - size.height / 2, area.minY), area.maxY - size.height)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct LittleWindowView: View {
    @EnvironmentObject private var store: BrowserStore
    let tabID: UInt64
    let host: NSView
    let putBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TintStyle.defaultsKey) private var style = TintStyle.calm

    var body: some View {
        let tab = store.core.tab(id: tabID)
        let space = store.snapshot.spaces.first { s in
            s.today.contains { $0.id == tabID } || s.pinned.contains { $0.id == tabID } || s.favorites.contains { $0.id == tabID }
        }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Room for the traffic lights.
                Spacer().frame(width: 64)
                if let tab {
                    FaviconImage(tab: tab, size: 14)
                    Text(tab.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Text(tab.host)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: putBack) {
                    Label("Open in Sidebar", systemImage: "sidebar.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Put this tab back in the main window")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(WindowDragArea())
            HostedView(view: host)
                .padding([.horizontal, .bottom], 6)
        }
        .background(
            LinearGradient(colors: Theme.gradient(for: RGB(space?.color ?? Theme.spaceColors[0]),
                                                  dark: colorScheme == .dark, active: true, style: style),
                           startPoint: .top, endPoint: .bottom)
        )
        .ignoresSafeArea()
    }
}

/// Puts an existing AppKit view into SwiftUI's layout.
private struct HostedView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Shown over the page while a sidebar tab is dragged onto it: where the
/// little window will appear.
struct LittleWindowDropPreview: View {
    let tab: TabInfo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(.primary.opacity(0.2)).frame(width: 8, height: 8) }
                    Spacer().frame(width: 6)
                    FaviconImage(tab: tab, size: 13)
                    Text(tab.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                VStack(spacing: 10) {
                    FaviconImage(tab: tab, size: 34)
                    Text("Drop to open in a little window")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(dark ? Color(white: 0.12) : .white))
                .padding([.horizontal, .bottom], 6)
            }
            .frame(width: 300, height: 360)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(dark ? Color(white: 0.2) : Color(white: 0.94)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

/// What a tab looks like while dragged: a compact pill like the selected row.
struct TabDragPreview: View {
    let tab: TabInfo

    var body: some View {
        HStack(spacing: 8) {
            FaviconImage(tab: tab)
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 30, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
    }
}
